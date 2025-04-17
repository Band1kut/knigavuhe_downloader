Enumeration FormWindow
  #main_window
EndEnumeration

Enumeration FormGadget
  #npt_url
  #npt_path
  #btn_path
  #lbl_authors
  #lbl_readers
  #progress_bar
  #src_book_name
  #src_authors
  #src_readers
  #src_info
  #tracker
  #btn_down
EndEnumeration

Structure err
  isErr.b
EndStructure

Structure names
  name.s
EndStructure

Structure book
  name.s
  Map authors.names()
  Map readers.names()
  cover.s
  url.s
EndStructure

Structure audio
  title.s
  url.s
EndStructure

Structure main
  id.i
  book.book
  List playlist.audio()
EndStructure

Global mainStruct.main, stop.b, downloading.b

Procedure updateDecription(path$, text$)
  If OpenFile(0, path$ + "Description.txt")
    FileSeek(0, Lof(0))
    WriteStringN(0, text$)
    CloseFile(0)
  EndIf
EndProcedure

Procedure.s findRegExpOne(text$, exp$, *err.err)
  Protected result$, re
  re = CreateRegularExpression(#PB_Any, exp$)
  If re
    If ExamineRegularExpression(re, text$)
      NextRegularExpressionMatch(re)
      result$ = RegularExpressionGroup(re, 1)
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

Procedure.s getPartString(s$, sep$, idx=0)
  Protected c
  
  s$ = RTrim(s$, sep$)
  c = CountString(s$, sep$)
  
  If idx = -1
    ProcedureReturn StringField(s$, c+1, sep$)
  ElseIf idx = 0
    ProcedureReturn s$
  EndIf 
  
  ProcedureReturn StringField(s$, c+1, sep$)
    
EndProcedure

Procedure.b prepareJSON(json$)
  If ParseJSON(0, json$)
    ExtractJSONStructure(JSONValue(0), mainStruct.main, main)
    FreeJSON(0)
    ProcedureReturn #True
  EndIf 
  ProcedureReturn #False
EndProcedure


Procedure.s downloadPage(url$, *err.err)
  Protected html$, NewMap Header$()
  Header$("cookie") = "new_design=1"
  Header$("User-Agent") = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36 Edg/135.0.0.0"
  
  HttpRequest = HTTPRequest(#PB_HTTP_Get, url$, "", 0, Header$())
  If HttpRequest
    If HTTPInfo(HTTPRequest, #PB_HTTP_StatusCode) = "200"
      *BufPage = HTTPMemory(HTTPRequest)
      html$ = PeekS(*BufPage, MemorySize(*BufPage),  #PB_UTF8|#PB_ByteLength)
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

Procedure.s getAuthors(Map tMap.names())
  Protected authors$
  ResetMap(tMap())

    While NextMapElement(tMap())
      If Len(authors$) > 0
        authors$ + ", " + tMap()\name
      Else
        authors$ = tMap()\name
      EndIf
    Wend
    ProcedureReturn authors$
EndProcedure

Procedure.s processPage(html$, *err.err)
  ;   Debug GetGadgetText(#npt_url)
  Protected json$, author$, reader$
  json$ = findRegExpOne(html$, "BookController\.enter\((.*?\})\);", *err)
  
  If json$
    If Not prepareJSON(json$)
      ProcedureReturn ~"Не удалось обработать JSON:\n" + json$
    EndIf 
    
    SetGadgetText(#src_book_name, mainStruct\book\name)
    
    author$ = getAuthors(mainStruct\book\authors())
    SetGadgetText(#src_authors, author$)
    
    If FindString(author$, ", ")
      SetGadgetText(#lbl_authors, "Авторы:")
    Else
      SetGadgetText(#lbl_authors, "Автор:")
    EndIf 
    
    reader$ = getAuthors(mainStruct\book\readers())
    SetGadgetText(#src_readers, reader$)
    
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

Procedure path_button()
  Protected defaultPath$, path$
  defaultPath$ = GetEnvironmentVariable("USERPROFILE") + "\Music\"  
  path$ = PathRequester("Выберите папку с историей раздач", defaultPath$)
  
  If path$ 
    SetGadgetText(#npt_path, path$)
    ProcedureReturn
  EndIf
  
  If Len(GetGadgetText(#npt_path)) = 0
    MessageRequester("Предупреждение", "Путь сохранения не может быть пустым", #PB_MessageRequester_Warning)
  EndIf 
  
EndProcedure

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

Procedure.q GetContentLength(Url$)
  Protected FileSizet.s=Space(20),FileSize.q, Size,hINET,hURL  
  hINET=InternetOpen_("PureBasic",0,0,0,0)  
  If hINET  
    hURL =InternetOpenUrl_(hINET,Url$,0,0,$80000000,0)  
    If hURL  
      Size=Len(FileSizet)  
      HttpQueryInfo_(hURL,#HTTP_QUERY_CONTENT_LENGTH,@FileSizet,@Size,#Null)  
      FileSize=Val(FileSizet)  
      InternetCloseHandle_(hURL)  
      InternetCloseHandle_(hINET)  
    Else 
      InternetCloseHandle_(hINET)  
    EndIf  
  EndIf  
  ProcedureReturn FileSize  
EndProcedure 

Procedure.s downFile(url$, name_file$, progressbarID=0)
  Protected content_length, Download, Progress, result$
  content_length = GetContentLength(url$)
  
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
          If progressbarID
            SetGadgetText(#tracker, ConvertBytes(Progress)+ "/" +ConvertBytes(content_length))
            SetGadgetState(#progress_bar, Int(Progress/content_length*100))            
          EndIf 
          
      EndSelect
      
      Delay(50)
    ForEver
    FinishHTTP(Download)
  Else
    result$ = "Ошибка загрузки"
  EndIf
  
  SetGadgetText(#tracker, ConvertBytes(content_length)+ "/" +ConvertBytes(content_length))
  SetGadgetState(#progress_bar, 0)
  ProcedureReturn result$
EndProcedure

Procedure.s downPlaylist(path$)
  Protected name_file$, path_file$, count, total$, error$
  total$ = Str(ListSize(mainStruct\playlist()))
  count = 1
  
  ResetList(mainStruct\playlist())
  ForEach mainStruct\playlist()
    SetGadgetText(#src_info, Str(count) + "/" + total$ + " " + mainStruct\playlist()\title)
    name_file$ = getPartString(mainStruct\playlist()\url, "/", -1)
    path_file$ = path$ + name_file$
    
    error$ = downFile(mainStruct\playlist()\url, path_file$, 1)
    If Len(error$ ) <> 0
      error$ + ~"\n" + "Скачано " + Str(count-1) + " аудиофайлов из " + total$
      Break
    EndIf 
    updateDecription(path$, name_file$)
    count +1
  Next
  ProcedureReturn error$
EndProcedure

Procedure.s CreateFullPath(path$)
  Protected Parts$, i, CurrentPath$
  
  If Right(path$, 1) = "\" Or Right(path$, 1) = "/"
    path$ = Left(path$, Len(path$) - 1)
  EndIf
  
  path$ = ReplaceString(path$, "/", "\")
  
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

Procedure.s prepareDir()
  Protected path$
  
  path$ = GetGadgetText(#npt_path)
  If Right(path$, 1) <> "\"
    path$ + "\"
  EndIf 
  
  path$ + getPartString(mainStruct\book\url, "/", -1) + "\"
  
  ProcedureReturn CreateFullPath(path$)
EndProcedure

Procedure.s checkURL(url$, *err.err)
  If FindString(url$, "knigavuhe.org/")
    ProcedureReturn ReplaceString(url$, "https://m.", "https://")
  EndIf 
  *err\isErr = 1  
  ProcedureReturn url$
EndProcedure

Procedure.s getDescription(html$, *err.err)
  Protected text$, descripton$
  text$ = "URL: " + GetGadgetText(#npt_url) + ~"\n\n"
  text$ + "Название: " + mainStruct\book\name + ~"\n"
  text$ + GetGadgetText(#lbl_authors) + " " + GetGadgetText(#src_authors) + ~"\n"
  text$ + GetGadgetText(#lbl_readers) + " " + GetGadgetText(#src_readers) + ~"\n\nОписание:\n"
  
  text$ + findRegExpOne(html$, ~"bookDescription\">(.*?)</", *err.err)  + ~"\n\nСписок файлов:"
  ProcedureReturn text$
EndProcedure


Procedure download_book()
  Protected html$, path$, url$, error$, err.err
  
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
  
  
  html$ = downloadPage(url$, @err)
  If err\isErr
    MessageRequester("Ошибка", ~"Не удалось скачать страницу:\n" + html$, #PB_MessageRequester_Error)
    ProcedureReturn 
  EndIf 
  
  result$ = processPage(html$, @err)
  If err\isErr
    MessageRequester("Ошибка", ~"Не удалось обработать страницу:\n" + result$, #PB_MessageRequester_Error)
    ProcedureReturn 
  EndIf 
  
  path$ = prepareDir()
  
  
  
  url$ = mainStruct\book\cover
  error$ = downFile(url$, path$+"cover.jpg")
  If error$ <> ""
    MessageRequester("Предупреждение", ~"Не удалось загрузить обложку: \n" + error$, #PB_MessageRequester_Warning)
  EndIf 
  
  SetGadgetText(#btn_down, "Прервать")
  
  descripton$ = getDescription(html$, @err)
  updateDecription(path$, descripton$)
  
  error$ = downPlaylist(path$)
  SetGadgetText(#tracker, "")
  SetGadgetText(#btn_down, "Скачать")
  SetGadgetText(#npt_url, "")
  
  If Len(error$) <> 0
    MessageRequester("Ошибка", error$, #PB_MessageRequester_Error)
  Else
    MessageRequester("Done!", "Загрузка завершена", #PB_MessageRequester_Info)
  EndIf
  
EndProcedure

Procedure StartDownloading(o)
  downloading = 1
  stop = 0
  
  download_book()
  
  ClearStructure(@mainStruct, main)
  
  downloading = 0
  stop = 0
EndProcedure

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
  
  SetGadgetText(#npt_path, GetEnvironmentVariable("USERPROFILE") + "\Music\")
EndProcedure

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
            stop = 1
          Else            
            CreateThread(@StartDownloading(), 0)
          EndIf 
          
      EndSelect
      
    Case #PB_Event_CloseWindow
      Break
  EndSelect
ForEver
CloseWindow(0)

End

  
; IDE Options = PureBasic 6.10 LTS (Windows - x64)
; CursorPosition = 191
; FirstLine = 179
; Folding = ----
; Optimizer
; EnableThread
; EnableXP
; DPIAware
; UseIcon = icon.ico
; Executable = downloader knigavuhe.org.exe
; Compiler = PureBasic 6.10 LTS - C Backend (Windows - x64)