{*****************************************************************
www:          http://sourceforge.net/projects/alcinoe/
Author(s):    St�phane Vander Clock (svanderclock@arkadia.com)
Sponsor(s):   Arkadia SA (http://www.arkadia.com)

product:      ALPhpRunner
Version:      3.54

Description:  ALPHPRunnerEngine is a simple but useful component for
              easily use php (any version) as a scripting language
              in Delphi applications. ALPhpRunnerEngine allows to
              execute the PHP scripts within the Delphi program without
              a WebServer. ALPHPRunnerEngine use the ISAPI DLL
              interface of PHP (php5isapi.dll) or the CGI/FastCGI
              interface (php-cgi.exe) of PHP to communicate with PHP engine.

Legal issues: Copyright (C) 1999-2011 by Arkadia Software Engineering

              This software is provided 'as-is', without any express
              or implied warranty.  In no event will the author be
              held liable for any  damages arising from the use of
              this software.

              Permission is granted to anyone to use this software
              for any purpose, including commercial applications,
              and to alter it and redistribute it freely, subject
              to the following restrictions:

              1. The origin of this software must not be
                 misrepresented, you must not claim that you wrote
                 the original software. If you use this software in
                 a product, an acknowledgment in the product
                 documentation would be appreciated but is not
                 required.

              2. Altered source versions must be plainly marked as
                 such, and must not be misrepresented as being the
                 original software.

              3. This notice may not be removed or altered from any
                 source distribution.

              4. You must register this software by sending a picture
                 postcard to the author. Use a nice stamp and mention
                 your name, street address, EMail address and any
                 comment you like to say.

Note :        If you use fastCGI (Socket) interface, you will need to start
              php-cgi separatly:

              php-cgi.exe -b host:port
              php-cgi.exe -b 127.0.0.1:8002

              Security
              --------
              Be sure to run the php binary as an appropriate userid
              Also, firewall out the port that PHP is listening on. In addition,
              you can set the environment variable FCGI_WEB_SERVER_ADDRS to
              control who can connect to the FastCGI.
              Set it to a comma separated list of IP addresses, e.g.:

              export FCGI_WEB_SERVER_ADDRS=199.170.183.28,199.170.183.71

              Tuning
              ------
              There are a few tuning parameters that can be tweaked to control
              the performance of FastCGI PHP. The following are environment
              variables that can be set before running the PHP binary:

              PHP_FCGI_CHILDREN  (default value: 0)
              !!! NOT WORK ON WINDOWS !!!

              This controls how many child processes the PHP process spawns. When the
              fastcgi starts, it creates a number of child processes which handle one
              page request at a time. Value 0 means that PHP willnot start additional
              processes and main process will handle FastCGI requests by itself. Note that
              this process may die (because of PHP_FCGI_MAX_REQUESTS) and it willnot
              respawned automatic. Values 1 and above force PHP start additioanl processes
              those will handle requests. The main process will restart children in case of
              their death. So by default, you will be able to handle 1 concurrent PHP page
              requests. Further requests will be queued. Increasing this number will allow
              for better concurrency, especially if you have pages that take a significant
              time to create, or supply a lot of data (e.g. downloading huge files via PHP).
              On the other hand, having more processes running will use more RAM, and letting
              too many PHP pages be generated concurrently will mean that each request will
              be slow. We recommend a value of 8 for a fairly busy site. If you have many,
              long-running PHP scripts, then you may need to increase this further.

              PHP_FCGI_MAX_REQUESTS (default value: 500)
              !!! set MaxRequestCount of TALPhpRunnerEngine < PHP_FCGI_MAX_REQUESTS !!!

              This controls how many requests each child process will handle before
              exitting. When one process exits, another will be created. This tuning is
              necessary because several PHP functions are known to have memory leaks. If the
              PHP processes were left around forever, they would be become very inefficient.

Know bug :

History :     29/01/2007: correct status missed in ALPhpRunnerECBServerSupportFunction
                          Add ALL_HTTP in servervariables object
              30/01/2007: Add fconnectioncount to not unload bug when action is processing
              10/10/2009: rename TALPhpRunnerEngine in TALPhpIsapiRunnerEngine
                          and add also TALPhpFastCgiRunnerEngine

Link :

Please send all your feedback to svanderclock@arkadia.com
**************************************************************}
unit ALPhpRunner;

interface

uses Windows,
     Classes,
     sysutils,
     ISAPI2,
     HttpApp,
     WinSock,
     Contnrs,
     SyncObjs,
     ALHttpCommon,
     ALIsapiHttp;

Const

  {------------------------------------------------------------}
  HSE_REQ_SEND_RESPONSE_HEADER_EX = (HSE_REQ_END_RESERVED + 16);
  HSE_REQ_MAP_URL_TO_PATH_EX      = (HSE_REQ_END_RESERVED + 12);

type

  {------------------------------}
  HSE_SEND_HEADER_EX_INFO = record
    pszStatus : LPCSTR;
    pszHeader : LPCSTR;
    cchStatus : DWORD;
    cchHeader : DWORD;
    fKeepConn : BOOL;
  end;
  LPHSE_SEND_HEADER_EX_INFO = ^HSE_SEND_HEADER_EX_INFO;
  THSE_SEND_HEADER_EX_INFO = HSE_SEND_HEADER_EX_INFO;

  {-------------------------}
  HSE_URL_MAPEX_INFO = record
    lpszPath : array[0..MAX_PATH - 1] of CHAR;
    dwFlags : DWORD;
    cchMatchingPath : DWORD;
    cchMatchingURL : DWORD;
    dwReserved1 : DWORD;
    dwReserved2 : DWORD;
  end;
  LPHSE_URL_MAPEX_INFO = ^HSE_URL_MAPEX_INFO;
  THSE_URL_MAPEX_INFO = HSE_URL_MAPEX_INFO;


{###############################################################################
Below the list of some server variables.
It's important to init them correctly
before to call the execute methode of
the ALPhpRunnerEngine because they
give to the engine all the neccessary
params

  URL                    (URL=/scripts/rooter.php)
  PATH_INFO              (PATH_INFO=/scripts/rooter.php)
  PATH_TRANSLATED        (PATH_TRANSLATED=C:\InetPub\scripts\rooter.php)
  SCRIPT_NAME            (SCRIPT_NAME=/scripts/rooter.php)
  SCRIPT_FILENAME        (SCRIPT_FILENAME=C:\InetPub\scripts\rooter.php)   => init by php to PATH_TRANSLATED if empty
  DOCUMENT_ROOT      	   (DOCUMENT_ROOT=C:\InetPub\)                       => Server variable introduced in PHP
                                                                              if set, It will be use to calculate
                                                                              Path_Translated (from SCRIPT_NAME first, and
                                                                              if not set them from PATH_INFO)

  REQUEST_METHOD         (REQUEST_METHOD=GET)
  SERVER_PROTOCOL        (SERVER_PROTOCOL=HTTP/1.1)
  QUERY_STRING           (QUERY_STRING=goto=newpost&t=1)                   => Don't forget that Query_string need to be
                                                                              url_encoded
  HTTP_CACHE_CONTROL     (HTTP_CACHE_CONTROL=)
  HTTP_DATE              (HTTP_DATE=)
  HTTP_ACCEPT            (HTTP_ACCEPT=*/*)
  HTTP_FROM              (HTTP_FROM=)
  HTTP_HOST              (HTTP_HOST=127.0.0.1)
  HTTP_IF_MODIFIED_SINCE (HTTP_IF_MODIFIED_SINCE=)
  HTTP_REFERER           (HTTP_REFERER=http://www.yahoo.fr)
  HTTP_USER_AGENT        (HTTP_USER_AGENT=Mozilla/4.0)
  HTTP_CONTENT_ENCODING  (HTTP_CONTENT_ENCODING=)
  CONTENT_TYPE           (CONTENT_TYPE=)
  CONTENT_LENGTH         (CONTENT_LENGTH=0)                                => set automatiquely with the size of the
                                                                              contentstream provided
  HTTP_CONTENT_VERSION   (HTTP_CONTENT_VERSION=)
  HTTP_DERIVED_FROM      (HTTP_DERIVED_FROM=)
  HTTP_EXPIRES	  			 (HTTP_EXPIRES=)
  HTTP_TITLE						 (HTTP_TITLE=)
  REMOTE_ADDR            (REMOTE_ADDR=127.0.0.1)
  REMOTE_HOST            (REMOTE_HOST=127.0.0.1)
  SERVER_PORT            (SERVER_PORT=80)
  HTTP_CONNECTION        (HTTP_CONNECTION=Keep-Alive)
  HTTP_COOKIE						 (HTTP_COOKIE=cookie1=value1; cookie2=Value2)
  HTTP_AUTHORIZATION     (HTTP_AUTHORIZATION=)

  SERVER_SOFTWARE      	 (SERVER_SOFTWARE=Microsoft-IIS/5.1)
  SERVER_NAME            (SERVER_NAME=127.0.0.1)
  AUTH_TYPE              (AUTH_TYPE=)
  REMOTE_USER            (REMOTE_USER=)
  REMOTE_IDENT           (REMOTE_IDENT=)


Below the list of all server variable found in the
code of Php5Isapi.dll

  ALL_HTTP
  APPL_MD_PATH
  APPL_PHYSICAL_PATH
  AUTH_PASSWORD
  AUTH_TYPE
  AUTH_USER
  CERT_COOKIE
  CERT_FLAGS
  CERT_ISSUER
  CERT_KEYSIZE
  CERT_SECRETKEYSIZE
  CERT_SERIALNUMBER
  CERT_SERVER_ISSUER
  CERT_SERVER_SUBJECT
  CERT_SUBJECT
  CONTENT_LENGTH
  CONTENT_TYPE
  DOCUMENT_ROOT
  HTTP_AUTHORIZATION
  HTTP_COOKIE
  HTTPS
  HTTPS_KEYSIZE
  HTTPS_SECRETKEYSIZE
  HTTPS_SERVER_ISSUER
  HTTPS_SERVER_SUBJECT
  INSTANCE_ID
  INSTANCE_META_PATH
  LOGON_USER
  ORIG_PATH_INFO
  ORIG_PATH_TRANSLATED
  PATH_INFO
  PATH_TRANSLATED
  PHP_AUTH_PW
  PHP_AUTH_USER
  PHP_SELF
  QUERY_STRING
  REMOTE_ADDR
  REMOTE_HOST
  REMOTE_USER
  REQUEST_METHOD
  REQUEST_URI
  SCRIPT_FILENAME
  SCRIPT_NAME
  SERVER_NAME
  SERVER_PORT
  SERVER_PORT_SECURE
  SERVER_PROTOCOL
  SERVER_SIGNATURE
  SERVER_SOFTWARE
  SSL_CLIENT_C
  SSL_CLIENT_CN
  SSL_CLIENT_DN
  SSL_CLIENT_EMAIL
  SSL_CLIENT_I_C
  SSL_CLIENT_I_CN
  SSL_CLIENT_I_DN
  SSL_CLIENT_I_EMAIL
  SSL_CLIENT_I_L
  SSL_CLIENT_I_O
  SSL_CLIENT_I_OU
  SSL_CLIENT_I_ST
  SSL_CLIENT_L
  SSL_CLIENT_O
  SSL_CLIENT_OU
  SSL_CLIENT_ST
  URL
###############################################################################}

  {---------------------------------}
  TALPhpRunnerEngine = class(Tobject)
  private
  protected
  public
    procedure Execute(ServerVariables: Tstrings;
                      RequestContentStream: Tstream;
                      ResponseContentStream: Tstream;
                      ResponseHeader: TALHTTPResponseHeader); overload; virtual; abstract;
    function  Execute(ServerVariables: Tstrings; RequestContentStream: Tstream): String; overload; virtual;
    procedure Execute(ServerVariables: Tstrings;
                      RequestContentString: String;
                      ResponseContentStream: Tstream;
                      ResponseHeader: TALHTTPResponseHeader); overload; virtual;
    function  Execute(ServerVariables: Tstrings; RequestContentString: String): String; overload; virtual;
    procedure ExecutePostUrlEncoded(ServerVariables: Tstrings;
                                    PostDataStrings: TStrings;
                                    ResponseContentStream: Tstream;
                                    ResponseHeader: TALHTTPResponseHeader;
                                    Const EncodeParams: Boolean=True); overload; virtual;
    function  ExecutePostUrlEncoded(ServerVariables: Tstrings;
                                    PostDataStrings: TStrings;
                                    Const EncodeParams: Boolean=True): String; overload; virtual;
  end;

  {---------------------------------------------------}
  TALPhpFastCgiRunnerEngine = class(TALPhpRunnerEngine)
  private
  protected
    procedure CheckError(Error: Boolean); virtual; abstract;
    Function  IOWrite(Var Buffer; Count: Longint): Longint; virtual; abstract;
    Function  IORead(var Buffer; Count: Longint): Longint; virtual; abstract;
    Procedure SendRequest(aRequest:String); virtual;
    function  ReadResponse: String; virtual;
  public
    procedure Execute(ServerVariables: Tstrings;
                      RequestContentStream: Tstream;
                      ResponseContentStream: Tstream;
                      ResponseHeader: TALHTTPResponseHeader); override;
  end;

  {----------------------------------------------------------------}
  TALPhpSocketFastCgiRunnerEngine = class(TALPhpFastCgiRunnerEngine)
  private
    FWSAData : TWSAData;
    Fconnected: Boolean;
    FSocketDescriptor: Integer;
    Ftimeout: integer;
    procedure Settimeout(const Value: integer);
  protected
    procedure CheckError(Error: Boolean); override;
    Function  IOWrite(Var Buffer; Count: Longint): Longint; override;
    Function  IORead(var Buffer; Count: Longint): Longint; override;
  public
    constructor Create; overload; virtual;
    constructor Create(aHost: String; APort: integer); overload; virtual;
    destructor  Destroy; override;
    Procedure Connect(aHost: String; APort: integer); virtual;
    Procedure Disconnect; virtual;
    property Connected: Boolean read FConnected;
    Property Timeout: integer read Ftimeout write Settimeout default 60000;
  end;

  {-------------------------------------------------------------------}
  TALPhpNamedPipeFastCgiRunnerEngine = class(TALPhpFastCgiRunnerEngine)
  private
    FServerPipe: Thandle;
    fServerterminationEvent: Thandle;
    fServerProcessInformation: TProcessInformation;
    FClientPipe: Thandle;
    FPipePath: String;
    Fconnected: Boolean;
    FRequestCount: Integer;
    FMaxRequestCount: Integer;
    fPhpInterpreterFileName: String;
    Ftimeout: integer;
  protected
    procedure CheckError(Error: Boolean); override;
    Function  IOWrite(Var Buffer; Count: Longint): Longint; override;
    Function  IORead(var Buffer; Count: Longint): Longint; override;
    Property  RequestCount: Integer read FRequestCount;
  public
    constructor Create; overload; virtual;
    constructor Create(aPhpInterpreterFilename: String); overload; virtual;
    destructor  Destroy; override;
    Procedure Connect(aPhpInterpreterFilename: String); virtual;
    Procedure Disconnect; virtual;
    procedure Execute(ServerVariables: Tstrings;
                      RequestContentStream: Tstream;
                      ResponseContentStream: Tstream;
                      ResponseHeader: TALHTTPResponseHeader); override;
    property Connected: Boolean read FConnected;
    Property Timeout: integer read Ftimeout write Ftimeout default 60000;
    Property MaxRequestCount: Integer read FMaxRequestCount write FMaxRequestCount Default 450;
  end;

  {-------------------------------------------------------}
  TALPhpNamedPipeFastCgiManager = class(TALPhpRunnerEngine)
  private
    fCriticalSection: TCriticalSection;
    fPhpInterpreterFilename: String;
    FWorkingPhpRunnerEngineCount: integer;
    FAvailablePhpRunnerengineLst: TobjectList;
    fProcessPoolSize: integer;
    fIsDestroying: Boolean;
    FMaxRequestCount: Integer;
    Ftimeout: integer;
  protected
    Function  AcquirePHPRunnerEngine: TALPhpNamedPipeFastCgiRunnerEngine;
    Procedure ReleasePHPRunnerEngine(aPHPRunnerEngine: TALPhpNamedPipeFastCgiRunnerEngine);
  public
    constructor Create; overload; virtual;
    constructor Create(aPhpInterpreter: String); overload; virtual;
    destructor  Destroy; override;
    procedure Execute(ServerVariables: Tstrings;
                      RequestContentStream: Tstream;
                      ResponseContentStream: Tstream;
                      ResponseHeader: TALHTTPResponseHeader); override;
    Property PhpInterpreter: String read fPhpInterpreterFilename write fPhpInterpreterFilename;
    Property ProcessPoolSize: integer read fProcessPoolSize write fProcessPoolSize default 8;
    Property MaxRequestCount: Integer read FMaxRequestCount write FMaxRequestCount Default 450;
    Property Timeout: integer read Ftimeout write Ftimeout default 60000;
  end;

  {-----------------------------------------------}
  TALPhpCgiRunnerEngine = class(TALPhpRunnerEngine)
  private
    fPhpInterpreterFilename: String;
  protected
  public
    constructor Create; overload; virtual;
    constructor Create(aPhpInterpreter: String); overload; virtual;
    procedure Execute(ServerVariables: Tstrings;
                      RequestContentStream: Tstream;
                      ResponseContentStream: Tstream;
                      ResponseHeader: TALHTTPResponseHeader); override;
    property PhpInterpreter: string read fPhpInterpreterFilename write fPhpInterpreterFilename;
  end;

  {-------------------------------------------------}
  TALPhpIsapiRunnerEngine = class(TALPhpRunnerEngine)
  private
    fConnectionCount: Integer;
    fDLLhandle: THandle;
    fHttpExtensionProcFunct: THttpExtensionProc;
    function GetDllLoaded: Boolean;
  protected
    procedure CheckError(Error: Boolean);
  public
    constructor Create; overload; virtual;
    constructor Create(const DLLFileName: String); overload; virtual;
    destructor  Destroy; override;
    procedure LoadDLL(const DLLFileName: String); virtual;
    Procedure UnloadDLL; virtual;
    procedure Execute(WebRequest: TALIsapiRequest;
                      ResponseContentStream: Tstream;
                      ResponseHeader: TALHTTPResponseHeader); overload; virtual;
    function  Execute(WebRequest: TALIsapiRequest): String; overload; virtual;
    procedure Execute(ServerVariables: Tstrings;
                      RequestContentStream: Tstream;
                      ResponseContentStream: Tstream;
                      ResponseHeader: TALHTTPResponseHeader); overload; override;
    Property  DLLLoaded: Boolean read GetDllLoaded;
    property  Dllhandle: THandle read fDLLhandle;
  end;

  {---------------------------------------}
  TALPhpIsapiRunnerBaseECB = class(Tobject)
  public
    ECB: TEXTENSION_CONTROL_BLOCK;
    ResponseContentStream: TStream;
    ResponseHeader: TALHTTPResponseHeader;
    constructor Create; virtual;
    Function GetServerVariableValue(aName: String): String; virtual; abstract;
  end;

  {--------------------------------------------------------------}
  TALPhpIsapiRunnerWebRequestECB = class(TALPhpIsapiRunnerBaseECB)
  public
    ServerVariablesObj: TWebRequest;
    constructor Create; override;
    Function GetServerVariableValue(aName: String): String; override;
  end;

  {------------------------------------------------------------}
  TALPhpIsapiRunnerTstringsECB = class(TALPhpIsapiRunnerBaseECB)
  public
    ServerVariablesObj: Tstrings;
    constructor Create; override;
    Function GetServerVariableValue(aName: String): String; override;
  end;

{--------------------}
function ALPhpIsapiRunnerECBGetServerVariable(hConn: HCONN; VariableName: PChar; Buffer: Pointer; var Size: DWORD ): BOOL; stdcall;
function ALPhpIsapiRunnerECBWriteClient(ConnID: HCONN; Buffer: Pointer; var Bytes: DWORD; dwReserved: DWORD): BOOL; stdcall;
function ALPhpIsapiRunnerECBReadClient(ConnID: HCONN; Buffer: Pointer; var Size: DWORD ): BOOL; stdcall;
function ALPhpIsapiRunnerECBServerSupportFunction(hConn: HCONN; HSERRequest: DWORD; Buffer: Pointer; Size: LPDWORD; DataType: LPDWORD ): BOOL; stdcall;

implementation

uses ALFcnWinSock,
     AlFcnString,
     AlFcnExecute,
     AlFcnMisc,
     ALWindows,
     AlFcnCGI;

//////////////////////////////
///// TALPhpRunnerEngine /////
//////////////////////////////

{***************************************************************************}
procedure TALPhpRunnerEngine.ExecutePostUrlEncoded(ServerVariables: Tstrings;
                                                   PostDataStrings: TStrings;
                                                   ResponseContentStream: Tstream;
                                                   ResponseHeader: TALHTTPResponseHeader;
                                                   Const EncodeParams: Boolean=True);
Var aURLEncodedContentStream: TstringStream;
    I: Integer;
begin
  aURLEncodedContentStream := TstringStream.create('');
  try

    if EncodeParams then ALHTTPEncodeParamNameValues(PostDataStrings);
    With PostDataStrings do
      for i := 0 to Count - 1 do
        If i < Count - 1 then aURLEncodedContentStream.WriteString(Strings[i] + '&')
        else aURLEncodedContentStream.WriteString(Strings[i]);

    ServerVariables.Values['REQUEST_METHOD'] := 'POST';
    ServerVariables.Values['CONTENT_TYPE'] := 'application/x-www-form-urlencoded';

    Execute(
            ServerVariables,
            aURLEncodedContentStream,
            ResponseContentStream,
            ResponseHeader
           );
  finally
    aURLEncodedContentStream.free;
  end;
end;

{***************************************************************************************************}
function TALPhpRunnerEngine.Execute(ServerVariables: Tstrings; RequestContentString: String): String;
var ResponseContentStream: TStringStream;
    ResponseHeader: TALHTTPResponseHeader;
    RequestContentStream: TstringStream;
begin
  RequestContentStream := TStringStream.Create(RequestContentString);
  ResponseContentStream := TStringStream.Create('');
  ResponseHeader := TALHTTPResponseHeader.Create;
  Try
    Execute(
            ServerVariables,
            RequestContentStream,
            ResponseContentStream,
            ResponseHeader
           );
    Result := ResponseContentStream.DataString;
  finally
    ResponseContentStream.Free;
    ResponseHeader.Free;
    RequestContentStream.Free;
  end;
end;

{*************************************************************}
procedure TALPhpRunnerEngine.Execute(ServerVariables: Tstrings;
                                     RequestContentString: String;
                                     ResponseContentStream: Tstream;
                                     ResponseHeader: TALHTTPResponseHeader);
var RequestContentStream: TstringStream;
begin
  RequestContentStream := TStringStream.Create(RequestContentString);
  Try
    Execute(
            ServerVariables,
            RequestContentStream,
            ResponseContentStream,
            ResponseHeader
           );
  finally
    RequestContentStream.Free;
  end;
end;

{****************************************************************************************************}
function TALPhpRunnerEngine.Execute(ServerVariables: Tstrings; RequestContentStream: Tstream): String;
var ResponseContentStream: TStringStream;
    ResponseHeader: TALHTTPResponseHeader;
begin
  ResponseContentStream := TStringStream.Create('');
  ResponseHeader := TALHTTPResponseHeader.Create;
  Try
    Execute(
            ServerVariables,
            RequestContentStream,
            ResponseContentStream,
            ResponseHeader
           );
    Result := ResponseContentStream.DataString;
  finally
    ResponseContentStream.Free;
    ResponseHeader.Free;
  end;
end;

{**************************************************************************}
function TALPhpRunnerEngine.ExecutePostUrlEncoded(ServerVariables: Tstrings;
                                                  PostDataStrings: TStrings;
                                                  Const EncodeParams: Boolean=True): String;
var ResponseContentStream: TStringStream;
    ResponseHeader: TALHTTPResponseHeader;
begin
  ResponseContentStream := TStringStream.Create('');
  ResponseHeader := TALHTTPResponseHeader.Create;
  Try
    ExecutePostUrlEncoded(
                          ServerVariables,
                          PostDataStrings,
                          ResponseContentStream,
                          ResponseHeader
                         );
    Result := ResponseContentStream.DataString;
  finally
    ResponseContentStream.Free;
    ResponseHeader.Free;
  end;
end;




/////////////////////////////////////
///// TALPhpFastCgiRunnerEngine /////
/////////////////////////////////////

{****************************************************************}
procedure TALPhpFastCgiRunnerEngine.SendRequest(aRequest: String);
Var P: Pchar;
    L: Integer;
    ByteSent: integer;
begin
  p:=@aRequest[1]; // pchar
  l:=length(aRequest);
  while l>0 do begin
    ByteSent:=IOWrite(p^,l);
    if ByteSent<=0 then raise Exception.Create('Connection close gracefully!');
    inc(p,ByteSent);
    dec(l,ByteSent);
  end;
end;

{******************************************************}
function TALPhpFastCgiRunnerEngine.ReadResponse: String;

  {--------------------------------------------------------}
  Procedure InternalRead(var aStr: String; aCount: Longint);
  var aBuffStr: String;
      aBuffStrLength: Integer;
  Begin
    if aCount <= 0 then exit;
    Setlength(aBuffStr,8192); // use a 8 ko buffer
                              // we can also use IOCtlSocket(Socket, FIONREAD, @Tam) Use to determine the amount of
                              // data pending in the network's input buffer that can be read from socket

    while aCount > 0 do begin
      aBuffStrLength := IORead(aBuffStr[1], length(aBuffStr));
      If aBuffStrLength <= 0 then raise Exception.Create('Connection close gracefully!');
      aStr := aStr + AlCopyStr(aBuffStr,1,aBuffStrLength);
      dec(aCount,aBuffStrLength);
    end;
  End;

Var ErrMsg: String;
    CurrMsgStr: String;
    CurrMsgContentlength: integer;
    CurrMsgPaddingLength: integer;
begin
  {init the result and local var}
  Result := '';
  ErrMsg := '';
  CurrMsgStr := '';

  {loop throught all message}
  While True do begin

    //msg is of the form :
    //version#type#requestIdB1#requestIdB0#contentLengthB1#contentLengthB0#paddingLength#reserved#contentData[contentLength]#paddingData[paddingLength];
    //   [1]  [2]    [3]           [4]          [5]              [6]            [7]        [8]           [9]

    {first read enalf of the message to know his size}
    while length(CurrMsgStr) < 7 do InternalRead(CurrMsgStr, 1);

    {first read enalf of the message to know the size}
    CurrMsgContentlength := (byte(CurrMsgStr[5]) shl 8) + byte(CurrMsgStr[6]);
                            //contentLengthB1             contentLengthB0
    CurrMsgPaddingLength := byte(CurrMsgStr[7]);
                            //paddingLength

    {put the full message in CurrMsgStr}
    InternalRead(CurrMsgStr, CurrMsgContentlength + CurrMsgPaddingLength + 8 - length(CurrMsgStr));

    {if message = FCGI_END_REQUEST}
    if CurrMsgStr[2] = #3 then Begin

      //The contentData component of a FCGI_END_REQUEST record has the form:
      //appStatusB3#appStatusB2#appStatusB1#appStatusB0#protocolStatus#reserved[3]
      //  [9]           [10]        [11]        [12]          [13]          [14]

      if ErrMsg <> '' then raise Exception.Create(ErrMsg)
      else if (length(CurrMsgStr) < 13) or (CurrMsgStr[13] <> #0 {FCGI_REQUEST_COMPLETE}) then raise Exception.Create('The Php has encountered an error while processing the request!')
      else exit; // ok, everything is ok so exit;

    End

    {else if message = FCGI_STDOUT}
    else if CurrMsgStr[2] = #6 then begin
      Result := Result + AlcopyStr(CurrMsgStr, 9, CurrMsgContentlength);
      CurrMsgStr := AlCopyStr(CurrMsgStr,9+CurrMsgContentlength+CurrMsgPaddingLength, Maxint);
    end

    {else if message = FCGI_STDERR}
    else if CurrMsgStr[2] = #7 then begin
      ErrMsg := ErrMsg + AlcopyStr(CurrMsgStr, 9, CurrMsgContentlength);
      CurrMsgStr := AlCopyStr(CurrMsgStr,9+CurrMsgContentlength+CurrMsgPaddingLength, Maxint);
    end;

    //else not possible, not in the fcgi spec, so skip the message,

  end;

end;

{********************************************************************}
procedure TALPhpFastCgiRunnerEngine.Execute(ServerVariables: Tstrings;
                                            RequestContentStream: Tstream;
                                            ResponseContentStream: Tstream;
                                            ResponseHeader: TALHTTPResponseHeader);

  {-------------------------------------------------------------------}
  {i not understand why in FCGI_PARAMS we need to specify te contentlength
   to max 65535 and in name value pair we can specify a length up to 17 Mo!
   anyway a content length of 65535 for the server variable seam to be suffisant}
  procedure InternalAddParam(var aStr : string; aName, aValue: string);
  var I, J   : integer;
      Len    : array[0..1] of integer;
      Format : array[0..1] of integer;
      Tam    : word;
  begin

    {----------}
    Len[0] := length(aName);
    if Len[0] <= 127 then Format[0] := 1
    else Format[0] := 4;
    {----------}
    Len[1] := length(aValue);
    if Len[1] <= 127 then Format[1] := 1
    else Format[1] := 4;
    {----------}
    Tam := Len[0] + Format[0] + Len[1] + Format[1];
    aStr := aStr +#1             +#4          +#0          +#1          +chr(hi(Tam))    +chr(lo(Tam))    +#0            +#0;
    //           +FCGI_VERSION_1 +FCGI_PARAMS +requestIdB1 +requestIdB0 +contentLengthB1 +contentLengthB0 +paddingLength +reserved
    J := length(aStr);
    SetLength(aStr, J + Tam);
    inc(J);
    for I := 0 to 1 do begin
      if Format[I] = 1 then aStr[J] := char(Len[I])
      else begin
        aStr[J]   := char(((Len[I] shr  24) and $FF) + $80);
        aStr[J+1] := char( (Len[I] shr  16) and $FF);
        aStr[J+2] := char( (Len[I] shr   8) and $FF);
        aStr[J+3] := char(  Len[I] and $FF);
      end;
      inc(J, Format[I]);
    end;
    move(aName[1], aStr[J], Len[0]);
    move(aValue[1], aStr[J + Len[0]], Len[1]);

    //the content data of the name value pair look like :
    //nameLengthB0#valueLengthB0#nameData[nameLength]#valueData[valueLength]
    //nameLengthB0#valueLengthB3#valueLengthB2#valueLengthB1#valueLengthB0#nameData[nameLength]#valueData[valueLength]
    //nameLengthB3#nameLengthB2#nameLengthB1#nameLengthB0#valueLengthB0#nameData[nameLength]#valueData[valueLength]
    //nameLengthB3#nameLengthB2#nameLengthB1#nameLengthB0#valueLengthB3#valueLengthB2#valueLengthB1#valueLengthB0#nameData[nameLength]#valueData[valueLength]

  end;

  {------------------------------------------}
  function InternalAddServerVariables: string;
  var aValue : string;
      I : integer;
  begin

    {build result}
    Result := '';
    for I := 0 to ServerVariables.Count - 1 do begin
      aValue := ServerVariables.ValueFromIndex[i];
      if aValue <> '' then InternalAddParam(Result, ServerVariables.Names[I], aValue);
    end;

    {finalize Result with an empty FCGI_PARAMS}
    Result := Result +#1             +#4          +#0          +#1          +#0              +#0              +#0            +#0;
                    //FCGI_VERSION_1 +FCGI_PARAMS +requestIdB1 +requestIdB0 +contentLengthB1 +contentLengthB0 +paddingLength +reserved

  end;

var aResponseStr: String;
    aFormatedRequestStr : string;
    Tam : word;
    P1: integer;
    S1 : String;
begin

  {init aFormatedRequestStr from aRequestStr}
  aFormatedRequestStr := '';
  if assigned(RequestContentStream) then begin
    P1 := 1;
    setlength(S1, 8184);
    RequestContentStream.Position := 0;
    while P1 <= RequestContentStream.Size do begin
      Tam := RequestContentStream.Read(S1[1], 8184); // ok i decide to plit the message in 8ko, because php send me in FCGI_STDOUT message split in 8ko (including 8 bytes of header)
      inc(P1, Tam);
      aFormatedRequestStr := aFormatedRequestStr + #1             +#5         +#0          +#1          +chr(hi(Tam))    +chr(lo(Tam))    +#0            +#0       +AlCopyStr(S1,1,Tam);
                                                 //FCGI_VERSION_1 +FCGI_STDIN +requestIdB1 +requestIdB0 +contentLengthB1 +contentLengthB0 +paddingLength +reserved +contentData[contentLength]
    end;

    {For securty issue... if content_length badly set then cpu can go to 100%}
    ServerVariables.Values['CONTENT_LENGTH']  := inttostr(RequestContentStream.Size);

  end

  {For securty issue... if content_length badly set then cpu can go to 100%}
  else ServerVariables.Values['CONTENT_LENGTH']  := '0';

  {finalize the aFormatedRequestStr with an empty FCGI_STDIN}
  aFormatedRequestStr :=  aFormatedRequestStr + #1             +#5         +#0          +#1          +#0              +#0              +#0            +#0;
                                              //FCGI_VERSION_1 +FCGI_STDIN +requestIdB1 +requestIdB0 +contentLengthB1 +contentLengthB0 +paddingLength +reserved

  SendRequest(
              #1             +#1                 +#0          +#1          +#0              +#8              +#0            +#0       +#0     +#1             +#1             +#0       +#0       +#0       +#0       +#0      +
            //FCGI_VERSION_1 +FCGI_BEGIN_REQUEST +requestIdB1 +requestIdB0 +contentLengthB1 +contentLengthB0 +paddingLength +reserved +roleB1 +FCGI_RESPONDER +FCGI_KEEP_CONN +reserved +reserved +reserved +reserved +reserved
                                                                                                                                     //contentData[contentLength]-----------------------------------------------------
              InternalAddServerVariables +
              aFormatedRequestStr
             );

  {----------}
  aResponseStr := ReadResponse;
  P1 := AlPos(#13#10#13#10,aResponseStr);
  if P1 <= 0 then raise Exception.Create('The Php has encountered an error while processing the request!');
  ResponseHeader.RawHeaderText := AlCopyStr(aResponseStr,1,P1-1);
  ResponseContentStream.Write(aResponseStr[P1 + 4], length(aResponseStr) - P1 - 3);

end;




///////////////////////////////////////////
///// TALPhpSocketFastCgiRunnerEngine /////
///////////////////////////////////////////

{********************************************************************************}
constructor TALPhpSocketFastCgiRunnerEngine.Create(aHost: String; APort: integer);
Begin
  create;
  Connect(aHost, APort);
End;

{*************************************************}
constructor TALPhpSocketFastCgiRunnerEngine.Create;
begin
  FWSAData.wVersion := 0;
  Fconnected:= False;
  FSocketDescriptor:= INVALID_SOCKET;
  Ftimeout:= 60000;
end;

{*************************************************}
destructor TALPhpSocketFastCgiRunnerEngine.Destroy;
begin
  If Fconnected then Disconnect;
  inherited;
end;

{*******************************************************************************}
procedure TALPhpSocketFastCgiRunnerEngine.Connect(aHost: String; APort: integer);

  {---------------------------------------------}
  procedure CallServer(Server:string; Port:word);
  var SockAddr:Sockaddr_in;
      IP: String;
  begin
    FSocketDescriptor:=Socket(AF_INET,SOCK_STREAM,IPPROTO_IP);
    CheckError(FSocketDescriptor=INVALID_SOCKET);
    FillChar(SockAddr,SizeOf(SockAddr),0);
    SockAddr.sin_family:=AF_INET;
    SockAddr.sin_port:=swap(Port);
    SockAddr.sin_addr.S_addr:=inet_addr(Pchar(Server));
    If SockAddr.sin_addr.S_addr = INADDR_NONE then begin
      checkError(ALHostToIP(Server, IP));
      SockAddr.sin_addr.S_addr:=inet_addr(Pchar(IP));
    end;
    CheckError(WinSock.Connect(FSocketDescriptor,SockAddr,SizeOf(SockAddr))=SOCKET_ERROR);
  end;

begin

  if FConnected then raise Exception.Create('Already connected');

  Try

    WSAStartup (MAKEWORD(2,2), FWSAData);
    CallServer(aHost,aPort);
    CheckError(setsockopt(FSocketDescriptor,SOL_SOCKET,SO_RCVTIMEO,PChar(@FTimeOut),SizeOf(Integer))=SOCKET_ERROR);
    CheckError(setsockopt(FSocketDescriptor,SOL_SOCKET,SO_SNDTIMEO,PChar(@FTimeOut),SizeOf(Integer))=SOCKET_ERROR);
    Fconnected := True;

  Except
    Disconnect;
    raise;
  end;

end;

{***************************************************}
procedure TALPhpSocketFastCgiRunnerEngine.Disconnect;
begin
  If Fconnected then begin
    ShutDown(FSocketDescriptor,SD_BOTH);
    CloseSocket(FSocketDescriptor);
    FSocketDescriptor := INVALID_SOCKET;
    if FWSAData.wVersion = 2 then WSACleanup;
    FWSAData.wVersion := 0;
    Fconnected := False;
  end;
end;

{*******************************************************************}
procedure TALPhpSocketFastCgiRunnerEngine.CheckError(Error: Boolean);
begin
  if Error then RaiseLastOSError;
end;

{*************************************************************************}
procedure TALPhpSocketFastCgiRunnerEngine.Settimeout(const Value: integer);
begin
  If Value <> Ftimeout then begin
    if FConnected then begin
      CheckError(setsockopt(FSocketDescriptor,SOL_SOCKET,SO_RCVTIMEO,PChar(@FTimeOut),SizeOf(Integer))=SOCKET_ERROR);
      CheckError(setsockopt(FSocketDescriptor,SOL_SOCKET,SO_SNDTIMEO,PChar(@FTimeOut),SizeOf(Integer))=SOCKET_ERROR);
    end;
    Ftimeout := Value;
  end;
end;

{***********************************************************************************}
function TALPhpSocketFastCgiRunnerEngine.IORead(var Buffer; Count: Longint): Longint;
begin
  Result := Recv(FSocketDescriptor,Buffer,Count,0);
  CheckError(Result = SOCKET_ERROR);
end;

{************************************************************************************}
function TALPhpSocketFastCgiRunnerEngine.IOWrite(Var Buffer; Count: Longint): Longint;
begin
  Result := Send(FSocketDescriptor,Buffer,Count,0);
  CheckError(Result =  SOCKET_ERROR);
end;




//////////////////////////////////////////////
///// TALPhpNamedPipeFastCgiRunnerEngine /////
//////////////////////////////////////////////

{*************************************************************************************}
constructor TALPhpNamedPipeFastCgiRunnerEngine.Create(aPhpInterpreterFilename: String);
begin
  Create;
  Connect(aPhpInterpreterFilename);
end;

{****************************************************}
constructor TALPhpNamedPipeFastCgiRunnerEngine.Create;
begin
  FServerPipe := INVALID_HANDLE_VALUE;
  FClientPipe := INVALID_HANDLE_VALUE;
  fServerterminationEvent := INVALID_HANDLE_VALUE;
  fServerProcessInformation.hProcess := INVALID_HANDLE_VALUE;
  fServerProcessInformation.hThread := INVALID_HANDLE_VALUE;
  fServerProcessInformation.dwProcessId := 0;
  fServerProcessInformation.dwThreadId := 0;
  FRequestCount := 0;
  FMaxRequestCount := 450;
  fPhpInterpreterFileName := 'php-cgi.exe';
  Fconnected:= False;
  Ftimeout := 60000;
end;

{****************************************************}
destructor TALPhpNamedPipeFastCgiRunnerEngine.Destroy;
begin
  if connected then disconnect;
  inherited;
end;

{************************************************************************************}
procedure TALPhpNamedPipeFastCgiRunnerEngine.Connect(aPhpInterpreterFilename: String);
Var aStartupInfo: TStartupInfo;
    aEnvironment: String;
begin
  if FConnected then raise Exception.Create('Already connected');

  //create the pipepath here because if we do it in the oncreate the
  //fpipepath can survive few seconds after the disconnection, making
  //some trouble in the next execute loop (pipe has been ended)
  FPipePath := '\\.\pipe\ALPhpFastCGIRunner-' + ALMakeKeyStrByGUID;

  //create the server pipe
  FServerPipe := CreateNamedPipe(
                                 Pchar(fpipePath),                                  //lpName
                      		       PIPE_ACCESS_DUPLEX,                                //dwOpenMode
		                             PIPE_TYPE_BYTE or PIPE_WAIT or PIPE_READMODE_BYTE, //dwPipeMode
                     		         PIPE_UNLIMITED_INSTANCES,                          //nMaxInstances
                     		         4096,                                              //nOutBufferSize
                                 4096,                                              //nInBufferSize
                                 0,                                                 //nDefaultTimeOut
                                 NiL                                                //lpSecurityAttributes
                                );
  checkerror(FServerPipe = INVALID_HANDLE_VALUE);
  try

    //Make FServerPipe inheritable.
    checkerror(not SetHandleInformation(FServerPipe, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT));

		//create the termination event
		fServerterminationEvent := CreateEvent(
                                           NiL,   //lpEventAttributes
                                           TRUE,  //bManualReset
                                           FALSE, //bInitialState
                                           NiL    //lpName
                                          );
    CheckError(fServerterminationEvent = INVALID_HANDLE_VALUE);
    Try

  		checkerror(not SetHandleInformation(fServerterminationEvent, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT));
      aEnvironment := AlGetEnvironmentString + '_FCGI_SHUTDOWN_EVENT_' + '=' + inttostr(fServerterminationEvent) + #0#0;

      // Set up the start up info struct.
      ZeroMemory(@aStartupInfo,sizeof(TStartupInfo));
      aStartupInfo.cb := sizeof(TStartupInfo);
      aStartupInfo.lpReserved := nil;
      aStartupInfo.lpReserved2 := nil;
      aStartupInfo.cbReserved2 := 0;
      aStartupInfo.lpDesktop := nil;
      aStartupInfo.dwFlags := STARTF_USESTDHANDLES;
      //FastCGI on NT will set the listener pipe HANDLE in the stdin of
      //the new process.  The fact that there is a stdin and NULL handles
      //for stdout and stderr tells the FastCGI process that this is a
      //FastCGI process and not a CGI process.
      aStartupInfo.hStdInput  := FServerPipe;
      aStartupInfo.hStdOutput := INVALID_HANDLE_VALUE;
      aStartupInfo.hStdError  := INVALID_HANDLE_VALUE;

      //Make the listener socket inheritable.
      checkerror(not SetHandleInformation(aStartupInfo.hStdInput, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT));

      // Launch the process that you want to redirect.
      CheckError(Not CreateProcess(
                                   PChar(aPhpInterpreterFilename),   // pointer to name of executable module
                                   nil,                              // pointer to command line string
                                   nil,                              // pointer to process security attributes
                                   NiL,                              // pointer to thread security attributes
                                   TrUE,                             // handle inheritance flag
                                   CREATE_NO_WINDOW,                 // creation flags
                                   Pchar(aEnvironment),              // pointer to new environment block
                                   nil,                              // pointer to current directory name
                                   aStartupInfo,                     // pointer to STARTUPINFO
                                   fServerProcessInformation         // pointer to PROCESS_INFORMATION
                                  ));

      CheckError(not WaitNamedPipe(Pchar(fPipePath), fTimeout));
      FClientPipe := CreateFile(
                                Pchar(fPipePath),                                   //lpFileName
                                GENERIC_WRITE or GENERIC_READ,                      //dwDesiredAccess
                                FILE_SHARE_READ or FILE_SHARE_WRITE,                //dwShareMode
                                nil,                                                //lpSecurityAttributes
                                OPEN_EXISTING,                                      //dwCreationDisposition
                                0,                                                  //dwFlagsAndAttributes
                                0                                                   //hTemplateFile
                               );
      CheckError(FClientPipe = INVALID_HANDLE_VALUE);

    Except
      CloseHandle(fServerterminationEvent);
      fServerterminationEvent := INVALID_HANDLE_VALUE;
      Raise;
    End;

  Except
    Closehandle(FServerPipe);
    FServerPipe := INVALID_HANDLE_VALUE;
    raise;
  end;
  FConnected := True;
  FRequestCount := 0;
  fPhpInterpreterFileName := aPhpInterpreterFilename;
end;

{******************************************************}
procedure TALPhpNamedPipeFastCgiRunnerEngine.Disconnect;
var lpExitCode: DWORD;
begin
  If Fconnected then begin

    //Send The Signal Shutdown, but it's seam than
    //php-cgi not handle it, it's simply set a flag in_shutdown
    //to 1 and not close the application
		SetEvent(fServerterminationEvent);

    //Force terminate the server is still active
		GetExitCodeProcess(fServerProcessInformation.hProcess,  lpExitCode);
		if (lpExitCode = STILL_ACTIVE) then TerminateProcess(fServerProcessInformation.hProcess, 1);

    //close all the handle
    CloseHandle(fServerProcessInformation.hProcess);
    fServerProcessInformation.hProcess := INVALID_HANDLE_VALUE;
    CloseHandle(fServerProcessInformation.hThread);
    fServerProcessInformation.hThread := INVALID_HANDLE_VALUE;
    fServerProcessInformation.dwProcessId := 0;
    fServerProcessInformation.dwThreadId := 0;
    CloseHandle(FClientPipe);
    FClientPipe := INVALID_HANDLE_VALUE;
    CloseHandle(fServerPipe);
    fServerPipe := INVALID_HANDLE_VALUE;
    CloseHandle(fServerterminationEvent);
    fServerterminationEvent := INVALID_HANDLE_VALUE;

    //set connected to false
    Fconnected := False;
    FRequestCount := 0;

  end;
end;

{**********************************************************************}
procedure TALPhpNamedPipeFastCgiRunnerEngine.CheckError(Error: Boolean);
begin
  if Error then RaiseLastOSError
end;

{**************************************************************************************}
function TALPhpNamedPipeFastCgiRunnerEngine.IORead(var Buffer; Count: Longint): Longint;
Var lpNumberOfBytesRead: DWORD;
    StartTickCount: Int64;
begin
  //Ok i don't found any other way than this loop to do a timeout !
  //timeout are neccessary if the php-cgi.exe dead suddenly for exemple
  //in the way without timout the readfile will never return freezing the application
  StartTickCount := ALGetTickCount64;
  Repeat
    CheckError(
               not PeekNamedPipe(
                                 FClientPipe,            // handle to pipe to copy from
                                 nil,                    // pointer to data buffer
                                 0,                      // size, in bytes, of data buffer
                                 nil,                    // pointer to number of bytes read
                                 @lpNumberOfBytesRead,   // pointer to total number of bytes available
                                 nil                     // pointer to unread bytes in this message
                                )
              );
    if lpNumberOfBytesRead > 0 then begin
      CheckError(not ReadFile(FClientPipe,Buffer,count,lpNumberOfBytesRead,nil));
      result := lpNumberOfBytesRead;
      break;
    end
    else result := 0;
    sleep(10); // this is neccessary to not use 100% CPU usage
  Until ALGetTickCount64 - StartTickCount > fTimeout;
end;

{***************************************************************************************}
function TALPhpNamedPipeFastCgiRunnerEngine.IOWrite(Var Buffer; Count: Longint): Longint;
Var lpNumberOfBytesWritten: DWORD;
begin
  CheckError(not WriteFile(FClientPipe,Buffer,Count,lpNumberOfBytesWritten,nil));
  result := lpNumberOfBytesWritten;
end;

{*****************************************************************************}
procedure TALPhpNamedPipeFastCgiRunnerEngine.Execute(ServerVariables: Tstrings;
                                                     RequestContentStream: Tstream;
                                                     ResponseContentStream: Tstream;
                                                     ResponseHeader: TALHTTPResponseHeader);
begin
  if (FMaxRequestCount > 0) and (FRequestCount >= FMaxRequestCount) then begin
    Disconnect;
    Connect(fPhpInterpreterFileName);
  end;
  inc(FRequestCount);

  inherited Execute(
                    ServerVariables,
                    RequestContentStream,
                    ResponseContentStream,
                    ResponseHeader
                   );
end;




////////////////////////////////////////////////
///// TALPhpConcurrencyFastCgiRunnerEngine /////
////////////////////////////////////////////////


{***********************************************}
constructor TALPhpNamedPipeFastCgiManager.Create;
begin
  fCriticalSection := TCriticalSection.create;
  fPhpInterpreterFilename := 'php-cgi.exe';
  FIsDestroying := False;
  FWorkingPhpRunnerEngineCount := 0;
  FAvailablePhpRunnerengineLst := TobjectList.Create(False);
  fProcessPoolSize := 8;
  FMaxRequestCount := 450;
  Ftimeout := 60000;
end;

{************************************************************************}
constructor TALPhpNamedPipeFastCgiManager.Create(aPhpInterpreter: String);
begin
  create;
  fPhpInterpreterFilename := aPhpInterpreter;
end;

{***********************************************}
destructor TALPhpNamedPipeFastCgiManager.Destroy;
Var i: integer;
begin

  {we do this to forbid any new thread to create a new transaction}
  fCriticalSection.Acquire;
  Try
    FIsDestroying := True;
  finally
    fCriticalSection.Release;
  end;

  {wait that all transaction are finished}
  while true do begin
    fCriticalSection.Acquire;
    Try
      if FWorkingPhpRunnerEngineCount <= 0 then break;
    finally
      fCriticalSection.Release;
    end;
    sleep(10); // to not use 100% CPU Usage
  end;

  {free all object}
  for i := 0 to FAvailablePhpRunnerengineLst.Count - 1 do
    FAvailablePhpRunnerengineLst[i].Free;
  FAvailablePhpRunnerengineLst.free;
  fCriticalSection.free;

  inherited;
end;

{************************************************************************************************}
function TALPhpNamedPipeFastCgiManager.AcquirePHPRunnerEngine: TALPhpNamedPipeFastCgiRunnerEngine;
begin
  fCriticalSection.Acquire;
  Try

    //for a stupid warning (D2007)
    Result := nil;

    //raise an exception if the object is destroying
    if FIsDestroying then raise exception.Create('Manager is destroying!');

    //Extract one engine
    If FAvailablePHPRunnerEngineLst.Count > 0 then begin
      Result := TALPhpNamedPipeFastCgiRunnerEngine(FAvailablePHPRunnerEngineLst[(FAvailablePHPRunnerEngineLst.count - 1)]);
      FAvailablePHPRunnerEngineLst.Delete(FAvailablePHPRunnerEngineLst.count - 1);
    end
    else begin
      Result := TALPhpNamedPipeFastCgiRunnerEngine.Create(fPhpInterpreterFilename);
      result.MaxRequestCount := FMaxRequestCount;
      result.Timeout := fTimeout;
    end;

    //increase the number of Working PHPRunnerEngine
    inc(FWorkingPHPRunnerEngineCount);

  finally
    fCriticalSection.Release;
  end;
end;

{*********************************************$*********************************************************************}
Procedure TALPhpNamedPipeFastCgiManager.ReleasePHPRunnerEngine(aPHPRunnerEngine: TALPhpNamedPipeFastCgiRunnerEngine);
begin
  fCriticalSection.Acquire;
  Try

    //decrease the number of Working PHPRunnerEngine
    Dec(FWorkingPHPRunnerEngineCount);
    if assigned(aPHPRunnerEngine) then begin
      If (FAvailablePHPRunnerEngineLst.Count < fProcessPoolSize) then FAvailablePHPRunnerEngineLst.Add(aPHPRunnerEngine)
      else aPHPRunnerEngine.free;
    end;

  finally
    fCriticalSection.Release;
  end;
end;

{************************************************************************}
procedure TALPhpNamedPipeFastCgiManager.Execute(ServerVariables: Tstrings;
                                                RequestContentStream: Tstream;
                                                ResponseContentStream: Tstream;
                                                ResponseHeader: TALHTTPResponseHeader);
Var aPhpRunnerEngine: TALPhpNamedPipeFastCgiRunnerEngine;
begin
  aPhpRunnerEngine := AcquirePHPRunnerEngine;
  try

    try

      aPhpRunnerEngine.Execute(
                               ServerVariables,
                               RequestContentStream,
                               ResponseContentStream,
                               ResponseHeader
                              );

    Except
      freeandnil(aPhpRunnerEngine);
      raise;
    end;

  finally
    ReleasePHPRunnerEngine(aPhpRunnerEngine)
  end;
end;




/////////////////////////////////
///// TALPhpCgiRunnerEngine /////
/////////////////////////////////

{****************************************************************}
constructor TALPhpCgiRunnerEngine.Create(aPhpInterpreter: String);
begin
  fPhpInterpreterFilename := aPhpInterpreter;
end;

{***************************************}
constructor TALPhpCgiRunnerEngine.Create;
begin
  Create('php-cgi.exe');
end;

{****************************************************************}
procedure TALPhpCgiRunnerEngine.Execute(ServerVariables: Tstrings;
                                        RequestContentStream: Tstream;
                                        ResponseContentStream: Tstream;
                                        ResponseHeader: TALHTTPResponseHeader);
begin
  AlCGIExec(
            fPhpInterpreterFilename,
            ServerVariables,
            RequestContentStream,
            ResponseContentStream,
            ResponseHeader
           );
end;




//////////////////////////////////////////////
/////ALPhpIsapiRunnerECBGetServerVariable/////
//////////////////////////////////////////////

{*********************************************************************************************************************************}
function ALPhpIsapiRunnerECBGetServerVariable(hConn: HCONN; VariableName: PChar; Buffer: Pointer; var Size: DWORD ): BOOL; stdcall;
Var TmpS: String;
    ln: Integer;
begin
  Try

    TmpS := TALPhpIsapiRunnerBaseECB(hConn).GetServerVariableValue(VariableName);
    LN := length(TmpS) + 1;
    If size < Dword(LN) then begin
      Result := False;
      SetLastError(ERROR_INSUFFICIENT_BUFFER);
      Size := Ln;
    end
    else begin
      Result := True;
      StrPCopy(PChar(buffer), tmpS);
      size:=Ln;
    end;

  Except
    Result := False;
  end;
end;

{**************************************************************************************************************************}
function ALPhpIsapiRunnerECBWriteClient(ConnID: HCONN; Buffer: Pointer; var Bytes: DWORD; dwReserved: DWORD): BOOL; stdcall;
begin
  Try
    TALPhpIsapiRunnerBaseECB(ConnID).ResponseContentStream.Write(Buffer^,Bytes);
    Result := True;
  except
    Result := False;
  end;
end;

{******************************************************************************************************}
function ALPhpIsapiRunnerECBReadClient(ConnID: HCONN; Buffer: Pointer; var Size: DWORD ): BOOL; stdcall;
begin
  Result := True;
  Size := 0;
end;

{*****************************************************************************************************************************************************}
function ALPhpIsapiRunnerECBServerSupportFunction(hConn: HCONN; HSERRequest: DWORD; Buffer: Pointer; Size: LPDWORD; DataType: LPDWORD ): BOOL; stdcall;
Var HeaderInfoEx : THSE_SEND_HEADER_EX_INFO;
    MapInfo : LPHSE_URL_MAPEX_INFO;
    DocumentRoot: String;
    TmpPath: String;    
    Ln: integer;
begin
  Try

    Case HSERRequest of

      {----------}
      HSE_REQ_SEND_RESPONSE_HEADER_EX: begin
                                         With TALPhpIsapiRunnerBaseECB(HCONN).ResponseHeader do begin
                                           Result := true;
                                           HeaderInfoEx := HSE_SEND_HEADER_EX_INFO(Buffer^);
                                           RawHeaderText := AlCopyStr(HeaderInfoEx.pszStatus,1,HeaderInfoEx.cchStatus) + #13#10 +
                                                            AlCopyStr(HeaderInfoEx.pszHeader,1,HeaderInfoEx.cchHeader);
                                         end;
                                       end;

      {----------}
      HSE_REQ_MAP_URL_TO_PATH_EX: begin
                                    MapInfo := LPHSE_URL_MAPEX_INFO(DataType);
                                    TmpPath := String(Pchar(Buffer));
                                    If TmpPath = '' then result := false
                                    else begin
                                      DocumentRoot := TALPhpIsapiRunnerBaseECB(hConn).GetServerVariableValue('DOCUMENT_ROOT');
                                      If DocumentRoot = '' then result := False
                                      else begin
                                        TmpPath := ExpandFilename(IncludeTrailingPathDelimiter(DocumentRoot)+ TmpPath);
                                        Ln := length(TmpPath) + 1;
                                        If Ln < MAX_PATH then begin
                                          result := False;
                                          SetLastError(ERROR_INSUFFICIENT_BUFFER);
                                        end
                                        else begin
                                          Result := true;
                                          StrPCopy(MapInfo^.lpszPath,TmpPath);
                                        end;
                                      end;
                                    end;
                                  end;

      Else Begin
        Result := False;
        SetLastError(ERROR_NO_DATA);
      end;

    end

  except
    Result := False;
  end;
end;


///////////////////////////////////
///// TALPhpIsapiRunnerEngine /////
///////////////////////////////////

{***********************************************************}
procedure TALPhpIsapiRunnerEngine.CheckError(Error: Boolean);
begin
	if Error then RaiseLastOSError;
end;

{*****************************************}
constructor TALPhpIsapiRunnerEngine.Create;
begin
  fConnectionCount := 0;
  fDLLhandle:=0;
  fHttpExtensionProcFunct := nil;
end;

{********************************************************************}
constructor TALPhpIsapiRunnerEngine.Create(const DLLFileName: String);
begin
  Create;
  loadDll(DLLFileName);
end;

{*****************************************}
destructor TALPhpIsapiRunnerEngine.Destroy;
begin
  UnloadDLL;
  inherited;
end;

{*****************************************************}
function TALPhpIsapiRunnerEngine.GetDllLoaded: Boolean;
begin
  result := fDLLhandle <> 0;
end;

{*******************************************************************}
procedure TALPhpIsapiRunnerEngine.LoadDLL(const DLLFileName: String);
Var GetExtensionVersionFunct: TGetExtensionVersion;
    Version: THSE_VERSION_INFO;
begin
  fDLLhandle := LoadLibrary(Pchar(DLLFileName));
  CheckError(fDLLhandle = 0);
  Try

    @fHttpExtensionProcFunct := GetProcAddress(fDLLHandle, 'HttpExtensionProc');
    CheckError(@fHttpExtensionProcFunct = nil);

    @GetExtensionVersionFunct := GetProcAddress(fDLLHandle, 'GetExtensionVersion');
    CheckError(@GetExtensionVersionFunct = nil);
    If not GetExtensionVersionFunct(Version) then raise exception.Create('Can not use the extension!');

  except
    UnloadDLL;
  end;
end;

{******************************************}
procedure TALPhpIsapiRunnerEngine.UnloadDLL;
Var TerminateExtensionFunct : TTerminateExtension;
begin
  If DLLLoaded then Begin
    while InterlockedCompareExchange(fconnectioncount, 0, 0) <> 0 do sleep(10);
    @TerminateExtensionFunct := GetProcAddress(fDLLHandle, 'TerminateExtension');
    If assigned(TerminateExtensionFunct) then TerminateExtensionFunct(HSE_TERM_MUST_UNLOAD);
    CheckError(not FreeLibrary(fDLLHandle));
    fHttpExtensionProcFunct := nil;
    fDLLHandle := 0;
  end;
end;

{********************************************************************}
procedure TALPhpIsapiRunnerEngine.Execute(WebRequest: TALIsapiRequest;
                                          ResponseContentStream: Tstream;
                                          ResponseHeader: TALHTTPResponseHeader);
Var aPhpRunnerECB: TALPhpIsapiRunnerWebRequestECB;
    aHttpExtensionProcResult: DWORD;
begin
  If not DLLLoaded then raise Exception.Create('DLL is not loaded!');

  aPhpRunnerECB := TALPhpIsapiRunnerWebRequestECB.Create;
  InterlockedIncrement(Fconnectioncount);
  Try

    With aPhpRunnerECB.ECB do begin
      lpszMethod := pchar(WebRequest.Method);
      lpszQueryString := pchar(WebRequest.Query);
      lpszPathInfo:= pchar(WebRequest.PathInfo);
      lpszPathTranslated:= pchar(WebRequest.PathTranslated);
      lpszContentType:= pchar(WebRequest.ContentType);

      cbTotalBytes:=WebRequest.ContentStream.Size;
      cbAvailable:=WebRequest.ContentStream.Size;
      If cbTotalBytes > 0 then begin
        GetMem(lpbData, cbTotalBytes);
        WebRequest.ContentStream.Position := 0;
        WebRequest.ContentStream.read(lpbData^, cbTotalBytes);
      end
      else lpbData := nil;
    end;

    aPhpRunnerECB.ServerVariablesObj := WebRequest;
    aPhpRunnerECB.ResponseContentStream := ResponseContentStream;
    aPhpRunnerECB.ResponseHeader := ResponseHeader;

    aHttpExtensionProcResult := fHttpExtensionProcFunct(aPhpRunnerECB.ECB);
    if aHttpExtensionProcResult <> HSE_STATUS_SUCCESS then raise exception.Create('The extension has encountered an error while processing the request!');

  finally
    With aPhpRunnerECB.ECB do
      if lpbData <> nil then FreeMem(lpbData, cbTotalBytes);
    aPhpRunnerECB.free;
    InterlockedDecrement(Fconnectioncount);
  end;
end;

{****************************************************************************}
function TALPhpIsapiRunnerEngine.Execute(WebRequest: TALIsapiRequest): String;
var ResponseContentStream: TStringStream;
    ResponseHeader: TALHTTPResponseHeader;
begin
  ResponseContentStream := TStringStream.Create('');
  ResponseHeader := TALHTTPResponseHeader.Create;
  Try
    Execute(
            WebRequest,
            ResponseContentStream,
            ResponseHeader
           );
    Result := ResponseContentStream.DataString;
  finally
    ResponseContentStream.Free;
    ResponseHeader.Free;
  end;
end;

{******************************************************************}
procedure TALPhpIsapiRunnerEngine.Execute(ServerVariables: Tstrings;
                                          RequestContentStream: Tstream;
                                          ResponseContentStream: Tstream;
                                          ResponseHeader: TALHTTPResponseHeader);
Var aPhpRunnerECB: TALPhpIsapiRunnerTstringsECB;
    aHttpExtensionProcResult: DWORD;
    WorkServerVariables: Tstrings;
    i: integer;
    S1, S2: String;
begin
  {exit if the dll is not loaded (off course)}
  If not DLLLoaded then raise Exception.Create('DLL is not loaded!');

  {Create local object}
  aPhpRunnerECB := TALPhpIsapiRunnerTstringsECB.Create;
  WorkServerVariables := TstringList.Create;
  InterlockedIncrement(Fconnectioncount);
  Try

    {init WorkServerVariables}
    WorkServerVariables.Assign(ServerVariables);

    {init aPhpRunnerECB.ECB}
    With aPhpRunnerECB.ECB do begin
      lpszMethod := pchar(WorkServerVariables.Values['REQUEST_METHOD']);
      lpszQueryString := pchar(WorkServerVariables.Values['QUERY_STRING']);
      lpszPathInfo:= pchar(WorkServerVariables.Values['PATH_INFO']);
      lpszPathTranslated:= pchar(WorkServerVariables.Values['PATH_TRANSLATED']);
      lpszContentType:= pchar(WorkServerVariables.Values['CONTENT_TYPE']);

      If assigned(RequestContentStream) then begin
        cbTotalBytes:=RequestContentStream.Size;
        cbAvailable:=RequestContentStream.Size;
        If cbTotalBytes > 0 then begin
          GetMem(lpbData, cbTotalBytes);
          RequestContentStream.Position := 0;
          RequestContentStream.read(lpbData^, cbTotalBytes);
        end
        else lpbData := nil;
      end
      else begin
        cbTotalBytes:=0;
        cbAvailable:=0;
        lpbData := nil;
      end;

      WorkServerVariables.Values['CONTENT_LENGTH'] := inttostr(cbTotalBytes);
    end;

    {update the ALL_HTTP value}
    S1 := '';
    For i := 0 to ServerVariables.Count - 1 do begin
      S2 := AlUpperCase(ServerVariables.Names[i])+': '+ServerVariables.ValueFromIndex[i];
      If AlPos('HTTP_',S2) = 1 then S1 := S1 + #13#10 + S2;
    end;
    If S1 <> '' then delete(S1,1,2);
    WorkServerVariables.Values['ALL_HTTP'] := S1;

    {init aPhpRunnerECB properties}
    aPhpRunnerECB.ServerVariablesObj := WorkServerVariables;
    aPhpRunnerECB.ResponseContentStream := ResponseContentStream;
    aPhpRunnerECB.ResponseHeader := ResponseHeader;

    aHttpExtensionProcResult := fHttpExtensionProcFunct(aPhpRunnerECB.ECB);
    if aHttpExtensionProcResult <> HSE_STATUS_SUCCESS then raise exception.Create('The extension has encountered an error while processing the request!');

  finally
    With aPhpRunnerECB.ECB do
      if lpbData <> nil then FreeMem(lpbData, cbTotalBytes);
    aPhpRunnerECB.free;
    WorkServerVariables.Free;
    InterlockedDecrement(Fconnectioncount);
  end;
end;




////////////////////////////////
///// TALPhpIsapiRunnerECB /////
////////////////////////////////

{******************************************}
constructor TALPhpIsapiRunnerbaseECB.Create;
begin
  ECB.cbSize:=sizeof(TEXTENSION_CONTROL_BLOCK);
  ECB.dwVersion:= MAKELONG(HSE_VERSION_MINOR, HSE_VERSION_MAJOR);
  ECB.ConnID:= THandle(Self);
  ECB.GetServerVariable:=@ALPhpIsapiRunnerECBGetServerVariable;
  ECB.WriteClient:=@ALPhpIsapiRunnerECBWriteClient;
  ECB.ReadClient:=@ALPhpIsapiRunnerECBReadClient;
  ECB.ServerSupportFunction:=@ALPhpIsapiRunnerECBServerSupportFunction;
  ECB.lpszLogData:='';
  ECB.lpszMethod := nil;
  ECB.lpszQueryString := nil;
  ECB.lpszPathInfo:= nil;
  ECB.lpszPathTranslated:= nil;
  ECB.lpszContentType:=nil;
  ECB.cbTotalBytes:=0;
  ECB.cbAvailable:=0;
  ECB.lpbData:=nil;
  ECB.dwHttpStatusCode := 0;
  ResponseContentStream := nil;
  ResponseHeader := nil;
end;

//////////////////////////////////////////
///// TALPhpIsapiRunnerWebRequestECB /////
//////////////////////////////////////////

{************************************************}
constructor TALPhpIsapiRunnerWebRequestECB.Create;
begin
  inherited;
  ServerVariablesObj := nil;
end;

{************************************************************************************}
function TALPhpIsapiRunnerWebRequestECB.GetServerVariableValue(aName: String): String;
begin
  Result := ServerVariablesObj.GetFieldByName(aName);
end;

////////////////////////////////////////
///// TALPhpIsapiRunnerTstringsECB /////
////////////////////////////////////////

{**********************************************}
constructor TALPhpIsapiRunnerTstringsECB.Create;
begin
  inherited;
  ServerVariablesObj := nil;
end;

{**********************************************************************************}
function TALPhpIsapiRunnerTstringsECB.GetServerVariableValue(aName: String): String;
begin
  Result := ServerVariablesObj.Values[aName];
end;

end.
