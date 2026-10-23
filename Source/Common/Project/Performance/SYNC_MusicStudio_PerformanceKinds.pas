unit SYNC_MusicStudio_PerformanceKinds;

// 演奏属性の固定キー。表示名と保存キーを分離し、PSD名やトラックIDを分類に使わない。
interface
uses System.JSON;
const
  PERFORMANCE_KEYS: array[0..5] of string = ('vocal','guitar','bass','drums','keyboard','other');
  PERFORMANCE_NAMES: array[0..5] of string = ('ボーカル','ギター','ベース','ドラム','キーボード','その他');
// 未選択は-1。自由入力を正規の属性へ暗黙変換しない。
function PerformanceKindIndex(const Key: string): Integer;
function PerformanceKindName(const Key: string): string;
// 共通演奏の参照は属性/固定ID/版を一組で持つ。nilは旧ローカル演奏として許す。
function ValidatePerformanceReference(Value: TJSONValue): Boolean;
implementation
uses System.SysUtils;
function ValidatePerformanceReference(Value: TJSONValue): Boolean;
var O: TJSONObject; G: TGUID; Key: string;
begin
  if Value=nil then Exit(True);
  Result := False; if not (Value is TJSONObject) then Exit; O := TJSONObject(Value);
  if not (O.GetValue('attribute') is TJSONString) or (PerformanceKindIndex(O.GetValue('attribute').Value)<0) then Exit;
  for Key in TArray<string>.Create('id','revision') do begin
    if not (O.GetValue(Key) is TJSONString) then Exit;
    try
      if Length(O.GetValue(Key).Value)=36 then G := StringToGUID('{'+O.GetValue(Key).Value+'}') else G := StringToGUID(O.GetValue(Key).Value);
      if IsEqualGUID(G,Default(TGUID)) then Exit;
    except on E: EConvertError do Exit; end;
  end;
  Result := True;
end;
function PerformanceKindIndex(const Key: string): Integer;
var I: Integer;
begin
  for I := Low(PERFORMANCE_KEYS) to High(PERFORMANCE_KEYS) do if PERFORMANCE_KEYS[I]=Key then Exit(I);
  Result := -1;
end;
function PerformanceKindName(const Key: string): string;
var I: Integer;
begin
  I := PerformanceKindIndex(Key);
  if I<0 then Result := '未選択' else Result := PERFORMANCE_NAMES[I];
end;
end.
