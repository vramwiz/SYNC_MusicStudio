unit SYNC_MusicStudio_PsdPreview;

// AIArtToPSD ArtPsdの境界検証/PackBits方式を適応した、読取専用のPSD合成画像プレビュー。
// RGB 8bit PSD v1の保存済み合成画像(raw/RLE)のみ。レイヤー切替と演奏変形は行わない。
interface
uses System.Classes, System.SysUtils, System.SyncObjs;
type
  TMusicStudioPsdPreviewJob = class(TThread)
  private
    FDone: TEvent;
    procedure Decode;
  protected
    procedure Execute; override;
  public
    Path, ErrorText: string;
    Width,Height: Integer;
    Pixels: TBytes; // premultiplied BGRA。UI所有者がDone後にTBitmapへコピーする。
    constructor Create(const FilePath: string);
    destructor Destroy; override;
    function Done: Boolean;
  end;
implementation
constructor TMusicStudioPsdPreviewJob.Create(const FilePath: string);
begin inherited Create(True); FreeOnTerminate := False; Path := FilePath; FDone := TEvent.Create(nil,True,False,''); end;
destructor TMusicStudioPsdPreviewJob.Destroy;
begin Terminate; WaitFor; FDone.Free; inherited; end;
function TMusicStudioPsdPreviewJob.Done: Boolean;
begin Result := (FDone.WaitFor(0)=wrSignaled) or Finished; end;
procedure TMusicStudioPsdPreviewJob.Decode;
var S: TFileStream; Header: array[0..25] of Byte; Channels,Compression,C,Y,X,N,Count,I: Integer;
  BlockSize,LayerSize: Cardinal; BlockEnd: Int64; LayerCount: SmallInt; HasAlpha: Boolean;
  Sizes: TArray<Word>; Planes: array[0..3] of TBytes; Row: TBytes; A: Byte;
  function U16: Word;
  var B: array[0..1] of Byte;
  begin S.ReadBuffer(B,2); Result := (Word(B[0]) shl 8) or B[1]; end;
  function U32: Cardinal;
  var B: array[0..3] of Byte;
  begin S.ReadBuffer(B,4); Result := (Cardinal(B[0]) shl 24) or (Cardinal(B[1]) shl 16) or (Cardinal(B[2]) shl 8) or B[3]; end;
  procedure SkipBlock;
  begin BlockSize := U32; if BlockSize > S.Size-S.Position then raise Exception.Create('PSDブロック境界が不正です'); S.Position := S.Position+BlockSize; end;
begin
  S := TFileStream.Create(Path,fmOpenRead or fmShareDenyNone);
  try
    if (S.Size < 40) or (S.Size > 1073741824) then raise Exception.Create('PSDサイズが非対応です（1GiBまで）');
    S.ReadBuffer(Header,SizeOf(Header));
    for I := 6 to 11 do if Header[I]<>0 then raise Exception.Create('PSD予約ヘッダーが不正です');
    if (Header[0]<>56) or (Header[1]<>66) or (Header[2]<>80) or (Header[3]<>83) or
      (Header[4]<>0) or (Header[5]<>1) or (Header[22]<>0) or (Header[23]<>8) or
      (Header[24]<>0) or (Header[25]<>3) then raise Exception.Create('合成画像表示はRGB 8bit PSD v1のみです');
    Channels := (Header[12] shl 8) or Header[13];
    Height := (Integer(Header[14]) shl 24) or (Header[15] shl 16) or (Header[16] shl 8) or Header[17];
    Width := (Integer(Header[18]) shl 24) or (Header[19] shl 16) or (Header[20] shl 8) or Header[21];
    if (Channels<3) or (Channels>16) or (Width<1) or (Height<1) or (Width>30000) or (Height>30000) or
      (Int64(Width)*Height>8388608) then raise Exception.Create('PSD合成画像は8M画素までです');
    SkipBlock; SkipBlock;
    LayerSize := U32; if LayerSize > S.Size-S.Position then raise Exception.Create('PSDレイヤー境界が不正です');
    BlockEnd := S.Position+LayerSize; HasAlpha := False;
    if LayerSize>0 then begin
      if LayerSize<4 then raise Exception.Create('PSDレイヤー長が不正です');
      BlockSize := U32; if (BlockSize>LayerSize-4) or (BlockSize=1) then raise Exception.Create('PSDレイヤー情報長が不正です');
      if BlockSize>=2 then begin LayerCount := SmallInt(U16); HasAlpha := LayerCount<0; end;
    end;
    S.Position := BlockEnd; Compression := U16;
    if not (Compression in [0,1]) then raise Exception.Create('PSD合成画像のZIP圧縮は未対応です');
    if Compression=1 then begin SetLength(Sizes,Channels*Height); for I := 0 to High(Sizes) do Sizes[I] := U16; end;
    for C := 0 to Channels-1 do begin
      if Terminated then Exit;
      if C<4 then SetLength(Planes[C],Width*Height);
      for Y := 0 to Height-1 do begin
        if Terminated then Exit;
        if Compression=0 then begin
          if C<4 then S.ReadBuffer(Planes[C][Y*Width],Width)
          else begin if Width>S.Size-S.Position then raise EReadError.Create('PSD合成画像が短すぎます'); S.Position := S.Position+Width; end;
        end else begin
          SetLength(Row,Sizes[C*Height+Y]); if Length(Row)>0 then S.ReadBuffer(Row[0],Length(Row)); X := 0; I := 0;
          while I<Length(Row) do begin
            N := Row[I]; Inc(I); if N=128 then Continue;
            if N<128 then Count := N+1 else Count := 257-N;
            if X+Count>Width then raise EReadError.Create('PSD PackBits行が長すぎます');
            if N<128 then begin
              if Count>Length(Row)-I then raise EReadError.Create('PSD PackBits行が短すぎます');
              if C<4 then Move(Row[I],Planes[C][Y*Width+X],Count); Inc(I,Count);
            end else begin
              if I>=Length(Row) then raise EReadError.Create('PSD PackBits値がありません');
              if C<4 then FillChar(Planes[C][Y*Width+X],Count,Row[I]); Inc(I);
            end;
            Inc(X,Count);
          end;
          if X<>Width then raise EReadError.Create('PSD PackBits行幅が一致しません');
        end;
      end;
    end;
    SetLength(Pixels,Width*Height*4);
    for I := 0 to Width*Height-1 do begin
      if (I mod 4096=0) and Terminated then begin Pixels := nil; Exit; end;
      A := 255; if HasAlpha and (Channels>=4) then A := Planes[3][I];
      Pixels[I*4] := (Integer(Planes[2][I])*A+127) div 255;
      Pixels[I*4+1] := (Integer(Planes[1][I])*A+127) div 255;
      Pixels[I*4+2] := (Integer(Planes[0][I])*A+127) div 255; Pixels[I*4+3] := A;
    end;
  finally S.Free; end;
end;
procedure TMusicStudioPsdPreviewJob.Execute;
begin
  try try Decode; except on E: Exception do begin ErrorText := E.Message; Pixels := nil; Width := 0; Height := 0; end; end;
  finally FDone.SetEvent; end;
end;
end.
