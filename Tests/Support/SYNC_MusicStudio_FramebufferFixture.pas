unit SYNC_MusicStudio_FramebufferFixture;

// Test-owned software D3D device: transparent object input is independent of
// a colored host framebuffer. Only borrowed COM pointers cross SDK callbacks.
interface
uses System.SysUtils, AviUtl2FilterTypes, Winapi.D3D11, Winapi.DXGIFormat;
type
  TMusicStudioFramebufferFixture = class
  private
    FDevice: ID3D11Device;
    FContext: ID3D11DeviceContext;
    FTexture: ID3D11Texture2D;
  public
    constructor Create;
    procedure Fill(Width,Height: Integer; Format: DXGI_FORMAT; const Data: TBytes);
    procedure RGBA(Width,Height: Integer; const Pixels: TArray<TPIXEL_RGBA>);
    function TexturePointer: Pointer;
  end;
implementation
uses Winapi.Windows, Winapi.D3DCommon;
constructor TMusicStudioFramebufferFixture.Create;
var Level: D3D_FEATURE_LEVEL;
begin
  inherited;
  if D3D11CreateDevice(nil,D3D_DRIVER_TYPE_WARP,0,0,nil,0,D3D11_SDK_VERSION,FDevice,Level,FContext)<0 then
    raise Exception.Create('Test-owned D3D WARP device unavailable');
end;
procedure TMusicStudioFramebufferFixture.Fill(Width,Height: Integer; Format: DXGI_FORMAT; const Data: TBytes);
var Desc: D3D11_TEXTURE2D_DESC; Initial: D3D11_SUBRESOURCE_DATA; Bpp: Integer;
begin
  Bpp := 4; if Format in [DXGI_FORMAT_R16G16B16A16_UNORM,DXGI_FORMAT_R16G16B16A16_FLOAT] then Bpp := 8;
  if Length(Data)<>Width*Height*Bpp then raise Exception.Create('Framebuffer fixture data size');
  Desc := Default(D3D11_TEXTURE2D_DESC); Desc.Width := Width; Desc.Height := Height;
  Desc.MipLevels := 1; Desc.ArraySize := 1; Desc.Format := Format; Desc.SampleDesc.Count := 1;
  Desc.Usage := D3D11_USAGE_DEFAULT;
  Initial := Default(D3D11_SUBRESOURCE_DATA); Initial.pSysMem := @Data[0]; Initial.SysMemPitch := Width*Bpp;
  FTexture := nil;
  if FDevice.CreateTexture2D(Desc,@Initial,FTexture)<0 then raise Exception.Create('Test framebuffer texture creation failed');
end;
procedure TMusicStudioFramebufferFixture.RGBA(Width,Height: Integer; const Pixels: TArray<TPIXEL_RGBA>);
var Bytes: TBytes;
begin
  SetLength(Bytes,Length(Pixels)*4); if Length(Bytes)>0 then Move(Pixels[0],Bytes[0],Length(Bytes));
  Fill(Width,Height,DXGI_FORMAT_R8G8B8A8_UNORM,Bytes);
end;
function TMusicStudioFramebufferFixture.TexturePointer: Pointer;
begin Result := Pointer(FTexture); end;
end.
