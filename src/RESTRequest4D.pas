unit RESTRequest4D;

interface

uses
  {$IF NOT (DEFINED(RR4D_INDY) or DEFINED(FPC) or DEFINED(RR4D_NETHTTP))}
    REST.Types,
  {$ENDIF}
  System.JSON, System.SysUtils, System.Classes, System.Generics.Collections,
  RESTRequest4D.Request.Contract, RESTRequest4D.Response.Contract, RESTRequest4D.Request.Adapter.Contract;

type

  TApiResponse = record
    StatusCode: Integer;
    Content: string;
    Headers: string;

    function IsSuccess: Boolean;

    function AsJsonObject: TJSONObject;
    function TryAsJsonObject(out Json: TJSONObject): Boolean;
  end;

  IRequest = RESTRequest4D.Request.Contract.IRequest;
  IRequestAdapter = RESTRequest4D.Request.Adapter.Contract.IRequestAdapter;
  IResponse = RESTRequest4D.Response.Contract.IResponse;

  TBeforeRequestCallback = procedure;

  TRequest = class
  public
    class function New: IRequest;
	  class procedure setDefaultBaseUrl(url: string);
	  class procedure setDefaultBearer(token: string);

    // GET
    class function Get(const Resource: string): TApiResponse; overload;
    class function Get(const Resource: string;
      const Params: TDictionary<string, string>): TApiResponse; overload;
    class function Get(const Resource: string; const Params: array of string)
      : TApiResponse; overload;

    // POST
    class function Post(const Resource: string; const Body: TJSONObject = nil)
      : TApiResponse;

    // PUT
    class function Put(const Resource: string; const Body: TJSONObject = nil)
      : TApiResponse;

    // DELETE
    class function Delete(const Resource: string): TApiResponse; overload;
    class function Delete(const Resource: string;
      const Params: TDictionary<string, string>): TApiResponse; overload;
    class function Delete(const Resource: string; const Params: array of string)
      : TApiResponse; overload;

  end;

{$IF NOT (DEFINED(RR4D_INDY) or DEFINED(FPC) or DEFINED(RR4D_NETHTTP))}
const
  poDoNotEncode = REST.Types.poDoNotEncode;
  poTransient = REST.Types.poTransient;
  poAutoCreated = REST.Types.poAutoCreated;
  {$IF COMPILERVERSION >= 33}
    poFlatArray = REST.Types.poFlatArray;
    poPHPArray = REST.Types.poPHPArray;
    poListArray = REST.Types.poListArray;
  {$ENDIF}

  pkCOOKIE = REST.Types.pkCOOKIE;
  pkGETorPOST = REST.Types.pkGETorPOST;
  pkURLSEGMENT = REST.Types.pkURLSEGMENT;
  pkHTTPHEADER = REST.Types.pkHTTPHEADER;
  pkREQUESTBODY = REST.Types.pkREQUESTBODY;
  {$IF COMPILERVERSION >= 32}
    pkFILE = REST.Types.pkFILE;
  {$ENDIF}
  {$IF COMPILERVERSION >= 33}
    pkQUERY = REST.Types.pkQUERY;
  {$ENDIF}
{$ENDIF}

implementation

uses
  {$IF DEFINED(FPC) and (not DEFINED(RR4D_INDY)) and (not DEFINED(RR4D_SYNAPSE))}
    RESTRequest4D.Request.FPHTTPClient;
  {$ELSEIF DEFINED(RR4D_INDY)}
    RESTRequest4D.Request.Indy;
  {$ELSEIF DEFINED(RR4D_NETHTTP)}
    RESTRequest4D.Request.NetHTTP;
  {$ELSEIF DEFINED(RR4D_SYNAPSE)}
    RESTRequest4D.Request.Synapse;
  {$ELSEIF DEFINED(RR4D_ICS)}
    RESTRequest4D.Request.ICS;
  {$ELSE}
    RESTRequest4D.Request.Client, FMX.Dialogs;
  {$ENDIF}

var
	gBaseUrl: string = '';
  gBearerToken: string = '';


//
// Helper para extrair texto da resposta
//
function ResponseText(const Resp: IResponse): string;
begin
  if Resp.Content <> '' then
    Exit(Resp.Content);

  if Length(Resp.RawBytes) > 0 then
    Exit(TEncoding.UTF8.GetString(Resp.RawBytes));

  Result := '';
end;

//
// Helper para aplicar query params
//
procedure ApplyParams(var Req: IRequest; const Params: TDictionary<string, string>);
var
  Pair: TPair<string, string>;
begin
  for Pair in Params do
    Req.AddParam(Pair.Key, Pair.Value);
end;

{ TApiResponse }

function TApiResponse.IsSuccess: Boolean;
begin
  Result := (StatusCode >= 200) and (StatusCode < 300);
end;

function TApiResponse.AsJsonObject: TJSONObject;
begin
  if Content.Trim = '' then
    raise Exception.Create('Response content is empty');

  Result := TJSONObject.ParseJSONValue(Content) as TJSONObject;

  if not Assigned(Result) then
    raise Exception.Create('Response is not a JSON object');
end;

function TApiResponse.TryAsJsonObject(out Json: TJSONObject): Boolean;
begin
  Json := nil;

  if Content.Trim = '' then
    Exit(False);

  try
    Json := TJSONObject.ParseJSONValue(Content) as TJSONObject;
    Result := Assigned(Json);
  except
    Json := nil;
    Result := False;
  end;
end;


class function TRequest.New: IRequest;
begin
  {$IF DEFINED(FPC) and (not DEFINED(RR4D_INDY)) and (not DEFINED(RR4D_SYNAPSE))}
    Result := TRequestFPHTTPClient.New;
  {$ELSEIF DEFINED(RR4D_INDY)}
    Result := TRequestIndy.New;
  {$ELSEIF DEFINED(RR4D_NETHTTP)}
    Result := TRequestNetHTTP.New;
  {$ELSEIF DEFINED(RR4D_SYNAPSE)}
    Result := TRequestSynapse.New;
  {$ELSEIF DEFINED(RR4D_ICS)}
    Result := TRequestICS.New;
  {$ELSE}
    Result := TRequestClient.New;
  {$ENDIF}
  
  if gBaseUrl <> '' then
	  Result.BaseURL(gBaseUrl);

	if gBearerToken <> '' then
	  Result.TokenBearer(gBearerToken);
end;


class procedure TRequest.setDefaultBearer(token: string);
begin
	gBearerToken := token;
end;

class procedure TRequest.setDefaultBaseUrl(url: string);
begin
	gBaseUrl := url;
end;


// ================= GET =================
//
class function TRequest.Get(const Resource: string): TApiResponse;
var
  Resp: IResponse;
begin
  Resp := TRequest.New.Resource(Resource).Get;

  Result.StatusCode := Resp.StatusCode;
  Result.Content := ResponseText(Resp);
  Result.Headers := Resp.Headers.Text;
end;

class function TRequest.Get(const Resource: string;
const Params: TDictionary<string, string>): TApiResponse;
var
  Resp: IResponse;
  Req: IRequest;
begin
  Req := TRequest.New.Resource(Resource);

  ApplyParams(Req, Params);
  Resp := Req.Get;

  Result.StatusCode := Resp.StatusCode;
  Result.Content := ResponseText(Resp);
  Result.Headers := Resp.Headers.Text;
end;

class function TRequest.Get(const Resource: string;
const Params: array of string): TApiResponse;
var
  Dict: TDictionary<string, string>;
  I: Integer;
begin
  Dict := TDictionary<string, string>.Create;
  try
    I := 0;
    while I < Length(Params) do
    begin
      Dict.Add(Params[I], Params[I + 1]);
      Inc(I, 2);
    end;

    Result := Get(Resource, Dict);
  finally
    Dict.Free;
  end;
end;

//
// ================= POST =================
//
class function TRequest.Post(const Resource: string; const Body: TJSONObject)
  : TApiResponse;
var
  Resp: IResponse;
  s: string;
begin
  Resp := TRequest.New.Resource(Resource).AddBody(Body).Post;

  Result.StatusCode := Resp.StatusCode;
  Result.Content := ResponseText(Resp);
  Result.Headers := Resp.Headers.Text;
end;

//
// ================= PUT =================
//
class function TRequest.Put(const Resource: string; const Body: TJSONObject)
  : TApiResponse;
var
  Resp: IResponse;
begin
  Resp := TRequest.New.Resource(Resource).AddBody(Body).Put;

  Result.StatusCode := Resp.StatusCode;
  Result.Content := ResponseText(Resp);
  Result.Headers := Resp.Headers.Text;
end;

//
// ================= DELETE =================
//
class function TRequest.Delete(const Resource: string): TApiResponse;
var
  Resp: IResponse;
begin
  Resp := TRequest.New.Resource(Resource).Delete;

  Result.StatusCode := Resp.StatusCode;
  Result.Content := ResponseText(Resp);
  Result.Headers := Resp.Headers.Text;
end;

class function TRequest.Delete(const Resource: string;
const Params: TDictionary<string, string>): TApiResponse;
var
  Resp: IResponse;
  Req: IRequest;
begin
  Req := TRequest.New.Resource(Resource);

  ApplyParams(Req, Params);
  Resp := req.Delete;

  Result.StatusCode := Resp.StatusCode;
  Result.Content := ResponseText(Resp);
  Result.Headers := Resp.Headers.Text;
end;

class function TRequest.Delete(const Resource: string;
const Params: array of string): TApiResponse;
var
  Dict: TDictionary<string, string>;
  I: Integer;
begin
  Dict := TDictionary<string, string>.Create;
  try
    I := 0;
    while I < Length(Params) do
    begin
      Dict.Add(Params[I], Params[I + 1]);
      Inc(I, 2);
    end;

    Result := Delete(Resource, Dict);
  finally
    Dict.Free;
  end;
end;
{
class function TRequest.Post(const Resource: string; const Body: TJSONObject)
  : TApiResponse;
var
 s: string;
begin
    Result := TRequest.New.Resource(Resource).AddBody(body).Post;
    s := Result.content;
    TThread.Synchronize(nil, procedure begin ShowMessage(s); end);
end;  }
	
end.
