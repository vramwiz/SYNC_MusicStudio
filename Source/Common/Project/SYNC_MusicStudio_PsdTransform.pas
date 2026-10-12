unit SYNC_MusicStudio_PsdTransform;

// 作品ごとのPSD配置。正規化座標を保持し、原本や共有設定を変更しない。
interface
uses System.JSON, System.Types;
type
  TMusicStudioPsdTransform = record
    HasBounds: Boolean;
    X,Y,Width,Height: Double;
    FlipX,FlipY: Boolean;
  end;
// 未設定/反転だけの場合は従来の矩形を維持する。境界外も許すが値は有限・有界。
function ReadMusicStudioPsdTransform(Value: TJSONValue; out Transform: TMusicStudioPsdTransform;
  out ErrorText: string): Boolean;
function ValidMusicStudioPsdTransform(const Transform: TMusicStudioPsdTransform): Boolean;
procedure WriteMusicStudioPsdTransform(Psd: TJSONObject; const Transform: TMusicStudioPsdTransform);
function MusicStudioTransformedRect(const Transform: TMusicStudioPsdTransform;
  FrameWidth,FrameHeight: Integer; const Legacy: TRect): TRect;
implementation
uses System.SysUtils, System.Math;
const BoundsKeys: array[0..3] of string = ('x','y','width','height');
      FlipKeys: array[0..1] of string = ('flipX','flipY');
function FiniteBetween(Value,Minimum,Maximum: Double): Boolean;
begin Result := not IsNan(Value) and not IsInfinite(Value) and (Value>=Minimum) and (Value<=Maximum); end;
function ValidMusicStudioPsdTransform(const Transform: TMusicStudioPsdTransform): Boolean;
begin
  Result := not Transform.HasBounds or (FiniteBetween(Transform.X,-4,4) and
    FiniteBetween(Transform.Y,-4,4) and FiniteBetween(Transform.Width,0.001,4) and
    FiniteBetween(Transform.Height,0.001,4));
end;
function ReadMusicStudioPsdTransform(Value: TJSONValue; out Transform: TMusicStudioPsdTransform;
  out ErrorText: string): Boolean;
var Obj: TJSONObject; N: Integer; Key: string;
begin
  Transform := Default(TMusicStudioPsdTransform); ErrorText := ''; Result := True;
  if Value=nil then Exit;
  Result := False; ErrorText := 'psd.transformはオブジェクト、位置は-4～4、サイズは0.001～4、反転は真偽値で指定してください。';
  if not (Value is TJSONObject) then Exit; Obj := TJSONObject(Value); N := 0;
  for Key in BoundsKeys do if Assigned(Obj.GetValue(Key)) then begin
    Inc(N); if not (Obj.GetValue(Key) is TJSONNumber) then Exit;
  end;
  if (N<>0) and (N<>4) then Exit;
  Transform.HasBounds := N=4;
  if Transform.HasBounds then begin
    Transform.X := TJSONNumber(Obj.GetValue('x')).AsDouble;
    Transform.Y := TJSONNumber(Obj.GetValue('y')).AsDouble;
    Transform.Width := TJSONNumber(Obj.GetValue('width')).AsDouble;
    Transform.Height := TJSONNumber(Obj.GetValue('height')).AsDouble;
  end;
  for Key in FlipKeys do if Assigned(Obj.GetValue(Key)) and not (Obj.GetValue(Key) is TJSONBool) then Exit;
  if Obj.GetValue('flipX') is TJSONBool then Transform.FlipX := TJSONBool(Obj.GetValue('flipX')).AsBoolean;
  if Obj.GetValue('flipY') is TJSONBool then Transform.FlipY := TJSONBool(Obj.GetValue('flipY')).AsBoolean;
  Result := ValidMusicStudioPsdTransform(Transform); if Result then ErrorText := '';
end;
procedure WriteMusicStudioPsdTransform(Psd: TJSONObject; const Transform: TMusicStudioPsdTransform);
var Obj: TJSONObject; Key: string;
  procedure Put(const Name: string; Value: TJSONValue);
  begin Obj.RemovePair(Name).Free; Obj.AddPair(Name,Value); end;
begin
  if not ValidMusicStudioPsdTransform(Transform) then raise EArgumentException.Create('PSD配置の範囲が不正です。');
  Obj := Psd.GetValue('transform') as TJSONObject;
  if Obj=nil then begin Obj := TJSONObject.Create; Psd.AddPair('transform',Obj); end;
  for Key in BoundsKeys do Obj.RemovePair(Key).Free;
  if Transform.HasBounds then begin
    Obj.AddPair('x',TJSONNumber.Create(Transform.X)); Obj.AddPair('y',TJSONNumber.Create(Transform.Y));
    Obj.AddPair('width',TJSONNumber.Create(Transform.Width)); Obj.AddPair('height',TJSONNumber.Create(Transform.Height));
  end;
  Put('flipX',TJSONBool.Create(Transform.FlipX)); Put('flipY',TJSONBool.Create(Transform.FlipY));
end;
function MusicStudioTransformedRect(const Transform: TMusicStudioPsdTransform;
  FrameWidth,FrameHeight: Integer; const Legacy: TRect): TRect;
var L,T: Integer;
begin
  Result := Legacy;
  if Transform.HasBounds and ValidMusicStudioPsdTransform(Transform) then begin
    L := Round(Transform.X*FrameWidth); T := Round(Transform.Y*FrameHeight);
    Result := Rect(L,T,L+Max(1,Round(Transform.Width*FrameWidth)),T+Max(1,Round(Transform.Height*FrameHeight)));
  end;
end;
end.
