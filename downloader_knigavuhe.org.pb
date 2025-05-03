; Перечисление идентификаторов окон
Enumeration FormWindow
  #main_window
EndEnumeration

; Перечисление идентификаторов элементов интерфейса
Enumeration FormGadget
  #npt_url          ; Поле ввода URL
  #npt_path         ; Поле ввода пути сохранения
  #btn_path         ; Кнопка выбора пути
  #lbl_authors      ; Метка "Автор(ы)"
  #lbl_readers      ; Метка "Чтец(ы)"
  #progress_bar     ; Прогресс-бар загрузки
  #src_book_name    ; Поле отображения названия книги
  #src_authors      ; Поле отображения авторов
  #src_readers      ; Поле отображения чтецов
  #src_info         ; Информационное поле (статус)
  #tracker          ; Трекер загрузки (размер файла)
  #btn_down         ; Кнопка скачивания/прерывания
EndEnumeration

; Структура для обработки ошибок
Structure err
  isErr.b           ; Флаг наличия ошибки (0/1)
EndStructure

; Структура для хранения имен (авторов/чтецов)
Structure names
  name.s            ; Строка с именем
EndStructure

; Структура данных о книге
Structure book
  name.s            ; Название книги
  Map authors.names() ; Ассоциативный массив авторов
  Map readers.names() ; Ассоциативный массив чтецов
  cover.s           ; URL основной обложки
  cover_alt.s       ; URL альтернативной обложки
  url.s             ; URL книги
EndStructure

; Структура данных аудиофайла
Structure audio
  title.s           ; Название трека
  url.s             ; URL трека
EndStructure

; Основная структура данных приложения
Structure main
  id.i              ; Идентификатор
  book.book         ; Данные книги
  List playlist.audio()       ; Основной плейлист
  List merged_playlist.audio(); Альтернативный плейлист
EndStructure

; Структура для хранения HTML-страницы
Structure page
  html.s            ; HTML-код страницы
EndStructure

; Глобальные переменные
Global mainStruct.main, stop.b, downloading

; Процедура обновления файла описания
Procedure updateDecription(path$, text$)
  If OpenFile(0, path$)
    FileSeek(0, Lof(0))  ; Перемещаемся в конец файла
    WriteStringN(0, text$)
    CloseFile(0)
  EndIf
EndProcedure

; Процедура поиска по регулярному выражению
Procedure.s findRegExpOne(text$, exp$, *err.err)
  Protected result$, re
  
  ; Создаем регулярное выражение
  re = CreateRegularExpression(#PB_Any, exp$, #PB_RegularExpression_DotAll)
  If re
    If ExamineRegularExpression(re, text$)
      NextRegularExpressionMatch(re)
      result$ = RegularExpressionGroup(re, 1)  ; Извлекаем первую группу
    Else
      *err\isErr = 1
      result$ = "Ошибка регулярного выражения:" + RegularExpressionError()
    EndIf
  Else
    *err\isErr = 1
    result$ = "Ошибка регулярного выражения:" + RegularExpressionError()
  EndIf
  
  FreeRegularExpression(re)
  ProcedureReturn result$
EndProcedure

; Процедура извлечения части строки по разделителю
Procedure.s getPartString(s$, sep$, idx=0)
  Protected c
  s$ = RTrim(s$, sep$)
  c = CountString(s$, sep$)
  
  If idx = -1
    ProcedureReturn StringField(s$, c+1, sep$)  ; Последняя часть
  ElseIf idx = 0
    ProcedureReturn s$                          ; Вся строка
  EndIf 
  
  ProcedureReturn StringField(s$, c+1, sep$)    ; Конкретная часть
EndProcedure

; Процедура подготовки JSON данных
Procedure.b prepareJSON(json$)
  If ParseJSON(0, json$)
    ExtractJSONStructure(JSONValue(0), mainStruct.main, main)
    FreeJSON(0)
    ProcedureReturn #True
  EndIf 
  ProcedureReturn #False
EndProcedure

; Процедура загрузки веб-страницы
Procedure.s downloadPage(url$, *err.err)
  Protected html$, NewMap Header$()
  ; Устанавливаем заголовки запроса
  Header$("cookie") = "new_design=1"
  Header$("User-Agent") = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36 Edg/135.0.0.0"
  
  HttpRequest = HTTPRequest(#PB_HTTP_Get, url$, "", 0, Header$())
  If HttpRequest
    If HTTPInfo(HTTPRequest, #PB_HTTP_StatusCode) = "200"
      *BufPage = HTTPMemory(HTTPRequest)
      html$ = PeekS(*BufPage, MemorySize(*BufPage), #PB_UTF8|#PB_ByteLength)
      FreeMemory(*BufPage)
    Else
      *err\isErr = 1
      html$ = ~"Ошибка выполнения запроса: \n"+url$+~"\n"+HTTPInfo(HTTPRequest, #PB_HTTP_ErrorMessage)
    EndIf 
  Else
    *err\isErr = 1
    html$ = ~"Ошибка создания запроса: \n"+url$
  EndIf 
  
  FinishHTTP(HttpRequest)
  FreeMap(Header$())
  ProcedureReturn html$
EndProcedure

; Процедура форматирования списка авторов/чтецов
Procedure.s getAuthors(Map tMap.names())
  Protected authors$
  ResetMap(tMap())
  While NextMapElement(tMap())
    If Len(authors$) > 0
      authors$ + ", " + tMap()\name  ; Добавляем разделитель для нескольких имен
    Else
      authors$ = tMap()\name         ; Первое имя в списке
    EndIf
  Wend
  ProcedureReturn authors$
EndProcedure

; Основная процедура обработки страницы
Procedure.s processPage(*page.page, *err.err)
  Protected json$, author$, reader$
  ; Ищем JSON данные в HTML
  json$ = findRegExpOne(*page\html, "BookController\.enter\((.*?\})\);", *err)
  
  If json$
    If Not prepareJSON(json$)  ; Парсим JSON
      ProcedureReturn ~"Не удалось обработать JSON:\n" + json$
    EndIf 
    
    ; Формируем имя файла для альтернативной обложки
    mainStruct\book\cover_alt = StringField(mainStruct\book\cover, 1, "-") + ".jpg"
    
    ; Обновляем интерфейс
    SetGadgetText(#src_book_name, mainStruct\book\name)
    
    author$ = getAuthors(mainStruct\book\authors())
    SetGadgetText(#src_authors, author$)
    
    ; Устанавливаем правильную форму слова "Автор(ы)"
    If FindString(author$, ", ")
      SetGadgetText(#lbl_authors, "Авторы:")
    Else
      SetGadgetText(#lbl_authors, "Автор:")
    EndIf 
    
    reader$ = getAuthors(mainStruct\book\readers())
    SetGadgetText(#src_readers, reader$)
    
    ; Устанавливаем правильную форму слова "Чтец(ы)"
    If FindString(reader$, ", ")
      SetGadgetText(#lbl_readers, "Чтецы:")
    Else
      SetGadgetText(#lbl_readers, "Чтец:")
    EndIf 
    
  Else
    ProcedureReturn ~"Не удалось получить JSON:\n" + json$
  EndIf
  
  ProcedureReturn ""
EndProcedure

; Обработчик кнопки выбора пути
Procedure path_button()
  Protected defaultPath$, path$
  defaultPath$ = GetEnvironmentVariable("USERPROFILE") + "\Music\"  
  path$ = PathRequester("Выберите папку для схранения", defaultPath$)
  
  If path$ 
    SetGadgetText(#npt_path, path$)
    ProcedureReturn
  EndIf
  
  If Len(GetGadgetText(#npt_path)) = 0
    MessageRequester("Предупреждение", "Путь сохранения не может быть пустым", #PB_MessageRequester_Warning)
  EndIf 
EndProcedure

; Форматирование размера файла
Procedure.s ConvertBytes(bytes)
  Protected result.s
  If bytes >= 1048576
    result = StrF(bytes / 1048576.0, 2) + "mb"
  ElseIf bytes >= 1024
    result = StrF(bytes / 1024.0, 2) + "kb"
  Else
    result = Str(bytes) + "b"
  EndIf
  ProcedureReturn result
EndProcedure

; Получение размера файла по URL
Procedure GetContentLength(url$)
  Protected file_size, Header$
  HttpRequest = HTTPRequest(#PB_HTTP_Get, url$, "", #PB_HTTP_HeadersOnly)
  If HttpRequest
    Header$ = HTTPInfo(HTTPRequest, #PB_HTTP_Headers)
    Header$ = StringField(Header$, 2, "Content-Length:")
    file_size = Val(StringField(Header$, 1, #LF$))
    FinishHTTP(HTTPRequest)
  EndIf 
  ProcedureReturn file_size
EndProcedure

; Процедура загрузки файла с отслеживанием прогресса
Procedure.s downFile(url$, name_file$, size_file=0)
  Protected content_length, Download, Progress, result$
  
  Download = ReceiveHTTPFile(url$, name_file$, #PB_HTTP_Asynchronous)
  If Download
    Repeat
      If stop
        AbortHTTP(Download)
      EndIf 
      
      Progress = HTTPProgress(Download)
      Select Progress
        Case #PB_HTTP_Success
          Break
          
        Case #PB_HTTP_Failed
          result$ = "Загрузка не удалась"
          Break
          
        Case #PB_HTTP_Aborted
          result$ = "Загрузка прервана"
          Break
          
        Default
          If size_file
            SetGadgetText(#tracker, ConvertBytes(Progress)+ "/" +ConvertBytes(size_file))
            SetGadgetState(#progress_bar, Int(Progress/size_file*100))            
          EndIf 
      EndSelect
      
      Delay(50)
    ForEver
    FinishHTTP(Download)
  Else
    result$ = "Ошибка загрузки"
  EndIf
  
  If size_file
    SetGadgetText(#tracker, ConvertBytes(size_file)+ "/" +ConvertBytes(size_file))
    SetGadgetState(#progress_bar, 0)
  EndIf
  ProcedureReturn result$
EndProcedure

; Удаление файлов по расширению
Procedure delFilesByExt(path$, ext$)
  If ExamineDirectory(0, path$, ext$)
    While NextDirectoryEntry(0)
      If DirectoryEntryType(0) = #PB_DirectoryEntry_File
        file$ = path$ + DirectoryEntryName(0)
        If Not DeleteFile(file$)
          RenameFile(file$, file$+".delete")
        EndIf
      EndIf
    Wend
    FinishDirectory(0)
  Else
    MessageRequester("Ошибка", "Не удалось открыть папку: " + directory$)
  EndIf
EndProcedure

; Проверка существования файла
Procedure.b fileExists(path$, name_file$, size_file=0)
  Protected result.b
  If ExamineDirectory(0, path$, name_file$)
    If NextDirectoryEntry(0)
      If Not size_file
        result = #True
      ElseIf DirectoryEntryType(0) = #PB_DirectoryEntry_File  
        If size_file = DirectoryEntrySize(0)
          result = #True
        EndIf
      EndIf
    EndIf 
    FinishDirectory(0)
  Else
    MessageRequester("Ошибка", "Не удалось открыть папку: " + directory$)
  EndIf
  ProcedureReturn result
EndProcedure

; Итерация по плейлисту и загрузка треков
Procedure.s iterPlaylist(path$, List pl.audio())
  Protected name_file$, path_file$, count, total$, error$, ext$, size_file
  total$ = Str(ListSize(pl()))
  
  ResetList(pl())
  ForEach pl()
    If stop
      error$ = "Загрузка прервана"
      Break
    EndIf 
    
    count +1
    SetGadgetText(#src_info, Str(count) + "/" + total$ + " " + pl()\title)
    
    ; Очищаем URL от параметров
    pl()\url = getPartString(pl()\url, "?", 1)
    ext$ = "."+getPartString(pl()\url, ".", -1)
    name_file$ = pl()\title + ext$
    
    path_file$ = path$ + name_file$
    size_file = GetContentLength(pl()\url)
    
    ; Пропускаем уже скачанные файлы
    If fileExists(path$, name_file$, size_file)
      SetGadgetText(#tracker, "Уже скачан")
      Continue
    EndIf 
    
    ; 3 попытки скачивания
    For i=1 To 3
      error$ = downFile(pl()\url, path_file$, size_file)
      If Len(error$) = 0
        Break
      EndIf 
      SetGadgetText(#tracker, "Попытка " + Str(i))
    Next
      
    If Len(error$) <> 0
      error$ + ~"\n" + "Скачано " + Str(count-1) + " аудиофайлов из " + total$
      Break
    EndIf 
  Next
  ProcedureReturn error$
EndProcedure

; Основная процедура загрузки плейлиста
Procedure.s downPlaylist(path$)
  Protected error$
  
  ; Пробуем основной плейлист
  error$ = iterPlaylist(path$, mainStruct\playlist())
  If Len(error$) = 0 Or stop
    ProcedureReturn error$
  EndIf 
  
  ; Если ошибка - пробуем альтернативный плейлист
  error$ + ~"\n\n Загрузка нечнется заново из альтернативного источника"
  MessageRequester("Ошибка", error$, #PB_MessageRequester_Error)
  
  delFilesByExt(path$, "*.mp3")
  
  error$ = iterPlaylist(path$, mainStruct\merged_playlist())
  
  If Len(error$) <> 0
    error$ + ~"\n\n Загрузка невозможна из обоих источников :("
  EndIf 
  
  ProcedureReturn error$
EndProcedure

; Создание полного пути с проверкой и созданием директорий
Procedure.s CreateFullPath(path$)
  Protected Parts$, i, CurrentPath$
  
  ; Нормализуем путь
  If Right(path$, 1) = "\" Or Right(path$, 1) = "/"
    path$ = Left(path$, Len(path$) - 1)
  EndIf
  
  path$ = ReplaceString(path$, "/", "\")
  
  ; Постепенно создаем все поддиректории
  Parts$ = StringField(path$, 1, "\")
  CurrentPath$ = Parts$
  
  For i = 2 To CountString(path$, "\") + 1
    Parts$ = StringField(path$, i, "\")
    CurrentPath$ + "\" + Parts$
    If FileSize(CurrentPath$) <> -2
      CreateDirectory(CurrentPath$)
    EndIf
  Next
  
  ProcedureReturn path$ + "\"  
EndProcedure

Procedure.s SanitizePath(path$)
  ; Список небезопасных символов в путях Windows
  Protected forbiddenChars$ = "\/:*!?<>|" + Chr(34) ; + кавычки
  Protected i, char$, safePath$
  
  ; Проверяем каждый символ в пути
  For i = 1 To Len(path$)
    char$ = Mid(path$, i, 1)
    
    ; Заменяем небезопасные символы на подчеркивание
    If FindString(forbiddenChars$, char$)
      safePath$ + "_"
    Else
      safePath$ + char$
    EndIf
  Next
  
  ; Удаляем ведущие и завершающие пробелы и точки (особенно важно для Windows)
  safePath$ = Trim(safePath$)
  While Right(safePath$, 1) = "."
    safePath$ = Left(safePath$, Len(safePath$) - 1)
  Wend
  
  ; Проверяем зарезервированные имена устройств Windows
  Protected fileName$ = GetFilePart(safePath$)
  Select UCase(fileName$)
    Case "CON", "PRN", "AUX", "NUL", 
         "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
         "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
      safePath$ + "_" ; Добавляем подчеркивание к зарезервированным именам
  EndSelect
  
  ProcedureReturn safePath$
EndProcedure

; Подготовка директории для сохранения
Procedure.s prepareDir()
  Protected path$
  
  path$ = GetGadgetText(#npt_path)
  If Right(path$, 1) <> "\"
    path$ + "\"
  EndIf 
  
  path$ + SanitizePath(mainStruct\book\name) + "\"
  
  ProcedureReturn CreateFullPath(path$)
EndProcedure

; Проверка и нормализация URL
Procedure.s checkURL(url$, *err.err)
  If FindString(url$, "knigavuhe.org/")
    ProcedureReturn ReplaceString(url$, "https://m.", "https://")
  EndIf 
  *err\isErr = 1  
  ProcedureReturn url$
EndProcedure

; Парсинг описания книги из HTML
Procedure.s parseDescription(*page.page)
  Protected s$ = findRegExpOne(*page\html, ~"bookDescription\">(.+?)" + "<\/div>", *err.err)
  If CreateRegularExpression(0, "<.*?>")
    s$ = ReplaceRegularExpression(0, s$, "")  ; Удаляем HTML-теги
  EndIf 
  ProcedureReturn s$
EndProcedure

; Формирование полного описания книги
Procedure.s getDescription(*page.page, *err.err)
  Protected text$, descripton$  
  text$ = "Название: " + mainStruct\book\name + ~"\n"
  text$ + GetGadgetText(#lbl_authors) + " " + GetGadgetText(#src_authors) + ~"\n"
  text$ + GetGadgetText(#lbl_readers) + " " + GetGadgetText(#src_readers) + ~"\n\nОписание:\n"
  
  text$ + parseDescription(*page)
  
  text$ + ~"\n\n" + GetGadgetText(#npt_url)
  ProcedureReturn text$
EndProcedure

; Основная процедура загрузки книги
Procedure download_book()
  Protected page.page, path$, url$, error$, err.err
  
  url$ = GetGadgetText(#npt_url)
  url$ = checkURL(url$, @err)
  
  If Len(GetGadgetText(#npt_path)) = 0
    MessageRequester("Ошибка", "Некоректный путь к папке", #PB_MessageRequester_Error)
    ProcedureReturn
  EndIf 
  
  If err\isErr
    MessageRequester("Ошибка", ~"Некорректный адрес URL:\n" + url$, #PB_MessageRequester_Error)
    ProcedureReturn 
  EndIf 
  
  SetGadgetText(#src_info, "Загрузка страницы")
  
  ; Загружаем страницу книги
  page\html = downloadPage(url$, @err)
  If err\isErr
    MessageRequester("Ошибка", ~"Не удалось скачать страницу:\n" + url$, #PB_MessageRequester_Error)
    ProcedureReturn 
  EndIf 
  
  ; Обрабатываем страницу
  result$ = processPage(@page, @err)
  If err\isErr
    MessageRequester("Ошибка", ~"Не удалось обработать страницу:\n" + result$, #PB_MessageRequester_Error)
    ProcedureReturn 
  EndIf 
  
  ; Подготавливаем директорию
  path$ = prepareDir()
  
  ; Загружаем обложку (если еще не существует)
  If Not fileExists(path$, "cover.jpg")
    SetGadgetText(#src_info, "Загрузка обложки")
    
    ; Пробуем альтернативный URL обложки
    error$ = downFile(mainStruct\book\cover_alt, path$+"cover.jpg")
    If error$ <> ""
      error$ = downFile(mainStruct\book\cover, path$+"cover.jpg")
    EndIf 
    
    If error$ <> ""
      MessageRequester("Предупреждение", ~"Не удалось загрузить обложку: \n" + error$, #PB_MessageRequester_Warning)
    EndIf 
    SetGadgetText(#tracker, "Готово")
  EndIf 
  
  SetGadgetText(#btn_down, "Прервать")
  
  ; Создаем файл описания (если еще не существует)
  If Not fileExists(path$, "Description.txt")
    SetGadgetText(#src_info, "Создание файла описания")
    descripton$ = getDescription(@page, @err)
    updateDecription(path$+"Description.txt", descripton$)
    SetGadgetText(#tracker, "Готово")
  EndIf 
  
  ClearStructure(@page, page)
  
  ; Загружаем плейлист
  error$ = downPlaylist(path$)
  SetGadgetText(#tracker, "")
  SetGadgetText(#btn_down, "Скачать")
  
  If Not stop
    SetGadgetText(#npt_url, "")
  EndIf 
  
  ; Выводим результат загрузки
  If Len(error$) <> 0
    If stop
      MessageRequester("Предупреждение", error$, #PB_MessageRequester_Warning)
    Else
      MessageRequester("Ошибка", error$, #PB_MessageRequester_Error)
    EndIf     
  Else
    If #PB_MessageRequester_Yes = MessageRequester("Done!", ~"Загрузка успешно завершена\nОткрыть папку с книгой?", #PB_MessageRequester_Info|#PB_MessageRequester_YesNo )
      RunProgram("explorer.exe", ~"\"" + path$ +~"\"", "")
    EndIf
  EndIf
EndProcedure

; Отключение элементов GUI
Procedure disableGui(state)
  DisableGadget(#npt_url, state)
  DisableGadget(#npt_path, state)
  DisableGadget(#btn_path, state)
EndProcedure

; Запуск загрузки в отдельном потоке
Procedure StartDownloading(o)
  downloading = 1
  stop = 0
  
  disableGui(#True)
  
  download_book()
  
  ClearStructure(@mainStruct, main)
  
  downloading = 0
  stop = 0
  disableGui(#False)
EndProcedure

; Создание главного окна
Procedure Openmain_window(x = 0, y = 0, width = 504, height = 272)
  OpenWindow(#main_window, x, y, width, height, "Downloader knigavuhe.org", #PB_Window_SystemMenu | #PB_Window_ScreenCentered)
  FrameGadget(#PB_Any, 8, 8, 488, 48, "Ссылка")
  StringGadget(#npt_url, 16, 24, 472, 24, "")
  FrameGadget(#PB_Any, 8, 64, 488, 48, "Папка для сохранения книги")
  StringGadget(#npt_path, 16, 80, 432, 24, "")
  ButtonGadget(#btn_path, 456, 80, 32, 24, "📁")
  TextGadget(#PB_Any, 16, 128, 64, 20, "Название:", #PB_Text_Right)
  TextGadget(#lbl_authors, 16, 152, 64, 20, "Автор:", #PB_Text_Right)
  TextGadget(#lbl_readers, 16, 176, 64, 20, "Чтец:", #PB_Text_Right)
  ProgressBarGadget(#progress_bar, 16, 240, 472, 20, 0, 100)
  TextGadget(#src_book_name, 88, 128, 400, 20, "")
  TextGadget(#src_authors, 88, 152, 312, 20, "")
  TextGadget(#src_readers, 88, 176, 312, 20, "")
  TextGadget(#src_info, 16, 208, 314, 20, "")
  TextGadget(#tracker, 330, 208, 158, 20, "", #PB_Text_Right)
  ButtonGadget(#btn_down, 408, 160, 80, 28, "Скачать")
  
  ; Устанавливаем путь по умолчанию
  SetGadgetText(#npt_path, GetEnvironmentVariable("USERPROFILE") + "\Music\")
EndProcedure

; Основной цикл программы
Openmain_window()

Repeat
  Define event = WaitWindowEvent()
  Select event
    Case #PB_Event_Gadget
      gadget = EventGadget()
      Select gadget
        Case #btn_path
          path_button()
          
        Case #btn_down
          If downloading
            stop = 1  ; Прерываем загрузку
          Else            
            CreateThread(@StartDownloading(), 0)  ; Запускаем в отдельном потоке
          EndIf 
      EndSelect
      
    Case #PB_Event_CloseWindow
      Break
  EndSelect
ForEver
CloseWindow(0)

End
