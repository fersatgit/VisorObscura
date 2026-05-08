//Writed in Delphi 7
//To compile from IDE press Ctrl+F9
//This is not a unit but a program. This hack reduses output file size.
unit VisorObscura;
{$IMAGEBASE $400000}{$E .exe}{$G-}{$R-}{$I-}{$M-}{$Y-}{$D-}{$C-}{$L-}{$Q-}{$O+}
interface
implementation
{$R 1.res}

uses
  Windows,Messages,FileSystem,OpenGL;

const
  IMAGE_FILE_LARGE_ADDRESS_AWARE=32;

{$SetPEFlags IMAGE_FILE_LARGE_ADDRESS_AWARE}  

label
  SectorLoaded;

const
  TIG_ART_TYPE_TILE          =0;
  TIG_ART_TYPE_WALL          =1;
  TIG_ART_TYPE_CRITTER       =2;
  TIG_ART_TYPE_PORTAL        =3;
  TIG_ART_TYPE_SCENERY       =4;
  TIG_ART_TYPE_INTERFACE     =5;
  TIG_ART_TYPE_ITEM          =6;
  TIG_ART_TYPE_CONTAINER     =7;
  TIG_ART_TYPE_MISC          =8;
  TIG_ART_TYPE_LIGHT         =9;
  TIG_ART_TYPE_ROOF          =10;
  TIG_ART_TYPE_FACADE        =11;
  TIG_ART_TYPE_MONSTER       =12;
  TIG_ART_TYPE_UNIQUE_NPC    =13;
  TIG_ART_TYPE_EYE_CANDY     =14;
  DIF_HAVE_LIGHT_LIST        =$001;
  DIF_HAVE_TILE_LIST         =$002;
  DIF_HAVE_ROOF_LIST         =$004;
  DIF_HAVE_OBJ_LIST          =$008;
  DIF_HAVE_TILE_SCRIPT_LIST  =$010;
  DIF_HAVE_SECTOR_SCRIPT_LIST=$020;
  DIF_HAVE_TOWNMAP           =$040;
  DIF_HAVE_APTITUDE_ADJ      =$080;
  DIF_HAVE_LIGHT_SCHEME      =$100;
  DIF_HAVE_SOUND_LIST        =$200;
  DIF_HAVE_BLOCK_LIST        =$400;

  SECTORS_MAP_WIDTH      =2048;
  SECTORS_ATLAS_WIDTH    =2048;
  SECTORS_ATLAS_ROW_WIDTH=SECTORS_ATLAS_WIDTH shr 6;
  TILES_ATLAS_WIDTH      =8192;
  TILES_ATLAS_ROW_WIDTH  =TILES_ATLAS_WIDTH div 40;

  VertexShader:   PAnsiChar='in vec4 pos;'+
                            'void main(){gl_Position=pos;}';

  FragmentShader: PAnsiChar='#version 130'#13#10+
                            '#define SECTORS_MAP_WIDTH 2048.'#13#10+
                            '#define TILES_ATLAS_WIDTH 8192.'#13#10+
                            '#define TILES_ATLAS_ROW_WIDTH 204.'#13#10+ //TILES_ATLAS_WIDTH/40
                            '#define SECTORS_ATLAS_WIDTH 2048.'#13#10+
                            '#define SECTORS_ATLAS_ROW_WIDTH 32.'#13#10+//SECTORS_ATLAS_WIDTH/64
                            'out vec4 Color;'+
                            'uniform usampler2D SectorsMap;'+
                            'uniform usampler2D SectorsAtlas;'+
                            'uniform sampler2D TileAtlas;'+
                            'uniform vec2 ScreenSize;'+
                            'uniform vec4 Params;'+ //x,y,Scale
                            'void main(){'+
                            'vec2 TexCoord;'+
                            'vec2 PixelCoords=vec2(gl_FragCoord.x,ScreenSize.y-gl_FragCoord.y)/Params.z+vec2(-Params.x,-Params.y)*(40.*64.);'+
                            'vec2 SectorCoords=PixelCoords/(40.*64.);'+
                            'uint SecId=texture(SectorsMap,trunc(SectorCoords)/SECTORS_MAP_WIDTH).r;'+
                            'vec2 TileCoord=(uvec2(mod(SecId,SECTORS_ATLAS_ROW_WIDTH),trunc(float(SecId)/SECTORS_ATLAS_ROW_WIDTH))+fract(SectorCoords))*64.;'+
                            'uint TileId=texture(SectorsAtlas,trunc(TileCoord)/SECTORS_ATLAS_WIDTH).r;'+
                            'if(float(TileId>>31)>0.){'+
                            'TileId=(TileId<<1)>>1;'+
                            'TexCoord=(1.-fract(TileCoord.yx)+vec2(mod(TileId,TILES_ATLAS_ROW_WIDTH),trunc(float(TileId)/TILES_ATLAS_ROW_WIDTH)))*40./TILES_ATLAS_WIDTH;'+
                            '}'+
                            'else '+
                            'TexCoord=(fract(TileCoord)+vec2(mod(TileId,TILES_ATLAS_ROW_WIDTH),trunc(float(TileId)/TILES_ATLAS_ROW_WIDTH)))*40./TILES_ATLAS_WIDTH;'+
                            'Color = vec4(texture(TileAtlas, TexCoord).rgb*1.5,(clamp(Params.z-1./40./64.,0,4./40./64.))/(4./40./64.));}';

type
 ArtHeader= packed record
            flags:         dword;
            frameRate:     dword;
            rotationCount: dword;
            paletteList:   array[0..3] of dword;
            actionFrame:   dword;
            frameCount:    dword;
            infoList:      array[0..7] of dword;
            sizeList:      array[0..7] of dword;
            dataList:      array[0..7] of dword;
            Palettes:      array[0..3,0..255] of dword;
            end;
 PArtHeader=^ArtHeader;
 ArtFrameInfo=packed record
              frameWidth:  dword;
              frameHeight: dword;
              frameSize:   dword;
              offsetX:     integer;
              offsetY:     integer;
              deltaX:      integer;
              deltaY:      integer;
              end;
 ArtFrameInfoArr=array[0..0] of ArtFrameInfo;
 PArtFrameInfo=^ArtFrameInfoArr;
 LightSerializedData=packed record
                     obj:        int64;
                     loc:        int64;
                     offset_x:   integer;
                     offset_y:   integer;
                     flags:      dword;
                     art_id:     dword;
                     r:          byte;
                     b:          byte;
                     g:          byte;
                     a:          byte;
                     tint_color: dword;
                     palette:    integer;
                     padding_2C: integer;
                     end;
  SectorTileList    =packed record
                     art_ids: array[0..4095] of dword;
                     difmask: array[0..127] of dword;
                     dif:     byte;
                     end;
  TTerrainHeader=packed record
                 version:           single;
                 flags:             dword;
                 width:             int64;
                 height:            int64;
                 base_terrain_type: integer;
                 padding_1C:        dword;
                 end;
  PTerrainHeader=^TTerrainHeader;
  RGBA          =packed record
                 case byte of
                 0:(value: dword);
                 1:(r,g,b,a: byte);
                 end;
  dwordarr      =array[0..high(integer) div sizeof(dword)-1] of dword;
  pdword        =^dwordarr;
  intarr        =array[0..high(integer) div sizeof(integer)-1] of integer;
  pint          =^intarr;
  wordarr       =array[0..0] of word;
  pword         =^wordarr;

var
  pfd:                                                      TPixelFormatDescriptor=(nSize:      sizeof(pfd);
                                                                                    nVersion:   1;
                                                                                    dwFlags:    PFD_DRAW_TO_WINDOW+PFD_SUPPORT_OPENGL+PFD_DOUBLEBUFFER;
                                                                                    iPixelType: PFD_TYPE_RGBA;
                                                                                    cColorBits: 32);
  p,tmp:                                                    PAnsiChar;
  pal:                                                      pdword;
  i,j:                                                      integer;
  k,m,n:                                                    dword;
  x,y:                                                      integer;
  Scale:                                                    single=1;
  UIScale:                                                  single;
  SecId:                                                    int64;
  wnd,DC,RC:                                                THandle;
  ClientRect:                                               TRECT;
  msg:                                                      tagMSG;
  WorldMapHTiles,WorldMapVTiles,Align:                      dword;
  WorldMapXPos,WorldMapYPos:                                single;
  WorldMapTileWidth,WorldMapTileHeight,WorldMapTileRowSize: dword;
  WorldMapWidth,WorldMapHeight,WorldMapSize,shaderProgram:  dword;

  WorldMapPathLen:      dword;
  WorldMapPath:         array[0..255] of AnsiChar;
  buf:                  array[0..4095] of AnsiChar;
  WorldMapRaster,SectorsColors: pdword;
  WorldMapTerrain:      pword;
  SectorsMap:           pword;
  Mouse:                TPoint;
  matrix:               array[0..15] of single=(1,0,0,0,
                                                0,1,0,0,
                                                0,0,1,0,
                                               -1,1,0,1);
  ScaledMatrix:         array[0..15] of single=(1,0,0,0,
                                                0,1,0,0,
                                                0,0,1,0,
                                               -1,1,0,1);
  front1,front2,front:  pint;
  front1len,front2len:  dword;
  TerrainColors:        array[0..31] of RGBA;
  TerrainNames:         array[0..31,0..31] of AnsiChar;
  LocationsCount:       dword;
  Locations:            array[0..255] of packed record
                                         namelen: dword;
                                         Name:    array[0..31] of AnsiChar;
                                         x,y:     integer;
                                         end;
  TerrainTilesCount:    dword;
  TerrainTileIdListLen: dword;
  TerrainTileIdList:    array[0..sqr(TILES_ATLAS_ROW_WIDTH)-1] of dword;
  FacadesCount:         dword;
  FacadesIndex:         array[0..511] of dword;
  TerrainAtlas:         PAnsiChar;
  SectorsCount:         dword;
  SectorsAtlas:         pdword;
  RandomSectorsOfs:     dword;
  RandomSectorsCount:   integer;
  RandomSectors:        array[0..SECTORS_ATLAS_ROW_WIDTH*SECTORS_ATLAS_ROW_WIDTH-1] of word;
  TileNamesCount:       dword;
  TileTypesOfs:         array[0..3] of dword;
  TileNames:            array[0..255] of dword;
  way:                  array[0..3] of integer;
  Tex:                  packed record
                        SectorsMap,SectorsAtlas,TileAtlas: integer;
                        end;
  uScreenSize,uParams,uTileAtlas,uSectorAtlas,uSectorMap:  dword;

procedure exchange(var a,b);assembler;
asm
  mov  ecx,[eax]
  xchg [edx],ecx
  mov  [eax],ecx
end;

procedure exchangew(var a,b);assembler;
asm
  mov  cx,[eax]
  xchg [edx],cx
  mov  [eax],cx
end;

function GetSectorFileName(x,y:integer; name: PAnsiChar): dword;
const
  qword_5B9968: array[0..15] of integer=(-1,1,(2 shl 26)+1,(1 shl 26)+1,(2 shl 26)+3,0,(2 shl 26)+2,-1,3,2,-1,-1,(1 shl 26)+3,-1,-1,-1);
var
  i,j,k,m,n:   dword;
  SecPath:     array[0..255] of AnsiChar;
  SecName:     array[0..31] of AnsiChar;
  SecId:       int64;
begin
  k:=y*WorldMapWidth+x;
  i:=WorldMapTerrain[k] shr 11;
  j:=(WorldMapTerrain[k] shr 6) and 31;
  if SectorsColors[k]=$FF00FF00 then
  begin
    move(WorldMapPath,SecPath,WorldMapPathLen);
    SecPath[WorldMapPathLen-1]:=#0;
    SecId:=int64((int64(y) shl 26)+WorldMapWidth-x)
  end
  else
  begin
    n:=(WorldMapTerrain[k] shr 2) and 15;
    lstrcpyA(SecPath,'terrain\');
    if (i=j)or(n=0) then
    begin
      SecId:=((WorldMapTerrain[k] and 2) shl 25)+(WorldMapTerrain[k] and 1);
      lstrcatA(SecPath,TerrainNames[i]);
    end
    else
    begin
      SecId:=qword_5B9968[n];
      if  SecId<>-1 then
      begin
        lstrcatA(SecPath,TerrainNames[i]);
        lstrcatA(SecPath,' to ');
        lstrcatA(SecPath,TerrainNames[j]);
      end
      else
      begin
        lstrcatA(SecPath,TerrainNames[j]);
        lstrcatA(SecPath,' to ');
        lstrcatA(SecPath,TerrainNames[i]);
        SecId:=qword_5B9968[15-n];
      end
    end;
  end;
  str(SecId,SecName);
  result:=wsprintfA(name,'%s\%s.sec',@SecPath,@SecName);
  name[result]:=#0;
end;

function WndProc(wnd,msg,wParam,lParam: dword): dword;stdcall;
label
  redraw;
var
  w,h,i,j:     integer;
  _x,_y,u,v: single;
begin
  case msg of
  WM_ERASEBKGND:;
       WM_PAINT:begin
         redraw:_x:=WorldMapXPos*Scale;
                _y:=WorldMapYPos*Scale;
                glClear(GL_COLOR_BUFFER_BIT);

                if Scale<8 then
                begin
                  //WorldMap
                  glLoadIdentity;
                  glTranslatef(-1,1,0);
                  glPixelZoom(Scale,-Scale);
                  glRasterPos2f(0,0);
                  glBitmap(0,0,0,0,_x,-_y,0);
                  glDrawPixels(WorldMapWidth,WorldMapHeight,GL_BGRA,GL_UNSIGNED_BYTE,WorldMapRaster);
                  //Terrain (sectors colors)
                 // glDrawPixels(WorldMapWidth,WorldMapHeight,GL_RGBA,GL_UNSIGNED_BYTE,SectorsColors);
                end;

                //Sectors
                glUseProgram(ShaderProgram);
                glUniform2f(uScreenSize,ClientRect.Right,ClientRect.Bottom);
                glUniform4f(uParams,WorldMapXPos,WorldMapYPos,Scale*(1/40/64),0);
                glUniform1i(uSectorMap,0);
                glUniform1i(uSectorAtlas,1);
                glUniform1i(uTileAtlas,2);
                glLoadIdentity;
                glBegin(GL_TRIANGLE_FAN);
                glColor4f(1,1,1,1);
                glVertex2f(-1,-1);
                glVertex2f(-1,1);
                glVertex2f(1,1);
                glVertex2f(1,-1);
                glEnd;
                glUseProgram(0);

                if Scale<128 then
                begin
                  //Circles around points of interest
                  glLoadMatrixf(@ScaledMatrix);
                  glTranslatef(WorldMapXPos,WorldMapYPos,0);
                  glCallList(256);

                  //Location names
                  glLoadIdentity;
                  glTranslatef(-1,1,0);
                  glColor3f(1,1,1);
                  glColor3f(1,1,1);
                  for w:=LocationsCount-1 downto 0 do
                    with Locations[w] do
                    begin
                      glRasterPos2f(0,0);
                      glBitmap(0,0,0,0,x*Scale+_x,-y*Scale-_y,0);
                      glCallLists(namelen,GL_UNSIGNED_BYTE,@name);
                    end;
                end; 

                //Sector info
                glLoadMatrixf(@matrix);
                glCallList(257);
                glColor3f(1,1,0);
                w:=trunc(Mouse.x/Scale-WorldMapXPos);
                h:=trunc(Mouse.y/Scale-WorldMapYPos);
                glRasterPos2f(0,20);
                glCallLists(wsprintfA(@buf,'Coords: %i,%i',WorldMapWidth-w-2,h),GL_UNSIGNED_BYTE,@buf); //Why 2?

                if (w>=0)and(w<=WorldMapWidth)and(h>=0)and(h<=WorldMapHeight) then
                begin
                  glRasterPos2f(0,50*UIScale);
                  glCallLists(GetSectorFileName(w,h,Buf),GL_UNSIGNED_BYTE,@buf);
                  glRasterPos2f(0,80*UIScale);
                  k:=h*WorldMapWidth+w;
                  i:=WorldMapTerrain[k] shr 11;
                  j:=(WorldMapTerrain[k] shr 6) and 31;
                  glCallLists(wsprintfA(@buf,'type1: %s',@TerrainNames[i]),GL_UNSIGNED_BYTE,@buf);
                  glRasterPos2f(0,110*UIScale);
                  glCallLists(wsprintfA(@buf,'type2: %s',@TerrainNames[j]),GL_UNSIGNED_BYTE,@buf);
                end;                

                SwapBuffers(DC);
                ValidateRect(wnd,0);
                end;
   WM_MOUSEMOVE:begin
                if wParam and MK_LBUTTON>0 then
                begin
                  WorldMapXPos:=WorldMapXPos+(loword(lParam)-Mouse.x)/Scale;
                  WorldMapYPos:=WorldMapYPos+(hiword(lParam)-Mouse.y)/Scale;
                end;
                Mouse.x:=loword(lParam);
                Mouse.y:=hiword(lParam);
                goto redraw;
                end;
  WM_MOUSEWHEEL:begin
                u:=1+smallint(hiword(wParam))/480;
                if (Scale*u>8000)or(Scale*u<0.0001) then
                  exit;
                Scale:=Scale*u;
                WorldMapXPos:=WorldMapXPos-(Mouse.x*u-Mouse.x)/Scale;
                WorldMapYPos:=WorldMapYPos-(Mouse.y*u-Mouse.y)/Scale;
                ScaledMatrix[0]:=(Scale+Scale)/ClientRect.Right;
                ScaledMatrix[5]:=-(Scale+Scale)/ClientRect.Bottom;
                goto redraw;
                end;
        WM_SIZE:begin
                GetClientRect(wnd,ClientRect);
                matrix[0]:=2/ClientRect.Right;
                matrix[5]:=-2/ClientRect.Bottom;
                ScaledMatrix[0]:=Scale*matrix[0];
                ScaledMatrix[5]:=Scale*matrix[5];
                glViewPort(0,0,ClientRect.Right,ClientRect.Bottom);
                glScissor(0,0,ClientRect.Right,ClientRect.Bottom);
                glUniform2f(uScreenSize,ClientRect.Right,ClientRect.Bottom);
                goto redraw;
                end;
       WM_CLOSE:ExitProcess(0);
  else
    result:=DefWindowProcW(wnd,msg,wParam,lParam);
  end;
end;

function GetTileName(TileId: dword): dword;
const
  dword_5BE8C0: array[0..15] of dword=(0,1,2,9,4,5,12,13,2,9,10,11,12,13,14,15);
  dword_5BE880: array[0..15] of dword=(0,1,8,3,4,5,6,7,8,3,10,11,6,7,14,15);
  off_5BB4E4:   PAnsiChar='06b489237ea5dc10';
var
  num1,num2,v1,v2,flip1,flip2,inout,nam1,nam2: dword;
begin
      num1 :=(TileId shr 22) and 63;
      num2 :=(TileId shr 16) and 63;
      v1   :=(TileId shr 12) and 15;
      v2   :=(TileId shr 9) and 7;
      {if TileId and 1>0 then
      begin
        v1:=dword_5BE8C0[v1];
        if dword_5BE8C0[v1]=dword_5BE880[v1] then
          inc(v2,8);
      end;}
      inout:=(TileId shr 7) and 2;
      flip1:=(TileId shr 7) and 1;
      flip2:=(TileId shr 6) and 1;

      nam1:=num1+TileTypesOfs[inout+flip1];
      nam2:=num2+TileTypesOfs[inout+flip2];

      {if v2>=8 then
        dec(v2,8);}

      if (v1=15)or(nam1=nam2) then
        result:=(nam1 shl 24)+((TileNamesCount-1) shl 16)+(ord(off_5BB4E4[v1]) shl 8)//sprintf(fname,"art\\tile\\%sbse%c%c.art",name1,off_5BB4E4[a3],a4 + 'a');
      else if v1=0 then
        result:=(nam2 shl 24)+((TileNamesCount-1) shl 16)+(ord(off_5BB4E4[0]) shl 8)//sprintf(fname,"art\\tile\\%sbse%c%c.art",name2,off_5BB4E4[0],a4 + 'a');
      else if nam1>=TileTypesOfs[1] then //if nam1 is indoor   //not sub_4EB7D0(name1, v11) then
        result:=(nam1 shl 24)+((TileNamesCount-1) shl 16)+(ord(off_5BB4E4[v1]) shl 8)//sprintf(fname,"art\\tile\\%sbse%c%c.art",name1,off_5BB4E4[a3],a4 + 'a');
      else if nam2>=TileTypesOfs[1] then //if nam2 is indoor //if not sub_4EB7D0(name2, v22) then
        result:=(nam2 shl 24)+((TileNamesCount-1) shl 16)+(ord(off_5BB4E4[15-v1]) shl 8)//sprintf(fname,"art\\tile\\%sbse%c%c.art",name2,off_5BB4E4[15 - a3],a4 + 'a');
      else if nam1<nam2 then
        result:=(nam1 shl 24)+(nam2 shl 16)+(ord(off_5BB4E4[v1]) shl 8)//sprintf(fname,"art\\tile\\%s%s%c%c.art",name1,name2,off_5BB4E4[a3],a4 + 'a');
      else
        result:=(nam2 shl 24)+(nam1 shl 16)+(ord(off_5BB4E4[15-v1]) shl 8);//sprintf(fname,"art\\tile\\%s%s%c%c.art",name2,name1,off_5BB4E4[15 - a3],a4 + 'a');
      inc(result,v2+ord('a'));
end;

procedure AddArtToAtlas(filename: PAnsiChar);
var
  tmp,p:         PAnsiChar;
  i,j,k,m,n,x,y: dword;
  FrameInfo:     PArtFrameInfo;
begin
  tmp:=GetFileData(filename,k,false); //not all files from facadenames.mes exists
  if tmp<>nil then
  begin
    k:=1; //palCount
    if PArtHeader(tmp)^.paletteList[1]>0 then
      inc(k);
    if PArtHeader(tmp)^.paletteList[2]>0 then
      inc(k);
    if PArtHeader(tmp)^.paletteList[3]>0 then
      inc(k);

    FrameInfo:=pointer(tmp+sizeof(ArtHeader)-sizeof(PArtHeader(tmp)^.palettes)+k*1024);
    if PArtHeader(tmp)^.flags and 1>0 then
      p:=pointer(LongInt(FrameInfo)+PArtHeader(tmp)^.frameCount*sizeof(ArtFrameInfo))
    else
      p:=pointer(LongInt(FrameInfo)+PArtHeader(tmp)^.rotationCount*PArtHeader(tmp)^.frameCount*sizeof(ArtFrameInfo));

    for i:=PArtHeader(tmp)^.frameCount-1 downto 0 do
      with FrameInfo[i] do
      begin
        k:=frameWidth*frameHeight;
        x:=0;
        repeat
          y:=ord(p^) and $7F;
          if ord(p^) and $80=0 then
          begin
            inc(p);
            fillchar(Buf[x],y,p^);
            inc(p);
          end
          else
          begin
            inc(p);
            move(p^,Buf[x],y);
            inc(p,y);
          end;
          inc(x,y);
        until x>=k;

        //reproject 78x40 tile to 40x40 tile for gaps elimination and size reduction
        m:=((TerrainTilesCount div TILES_ATLAS_ROW_WIDTH)*TILES_ATLAS_WIDTH+(TerrainTilesCount mod TILES_ATLAS_ROW_WIDTH))*120;
        inc(TerrainTilesCount);
        n:=19*78;
        for y:=39 downto 0 do
        begin
          k:=n;
          for x:=0 to 19 do
          begin
            PCardinal(TerrainAtlas+m)^  :=PArtHeader(tmp)^.palettes[0,ord(Buf[k])];
            PCardinal(TerrainAtlas+m+3)^:=PArtHeader(tmp)^.palettes[0,ord(Buf[k+1])];
            inc(m,6);
            dec(k,76);
          end;
          inc(m,(TILES_ATLAS_WIDTH-40)*3);
          if y and 1=0 then
            inc(n,2)
          else
            inc(n,78);
        end;
      end;
    VirtualFree(tmp,0,MEM_RELEASE);
  end;   
end;

procedure AddSecToAtlas(filename: PAnsiChar);
var
  tmp,p:         PAnsiChar;
  i,j,k,m,n,x,y: dword;
begin
  tmp:=GetFileData(filename,k);
  p:=tmp+4+sizeof(LightSerializedData)*PCardinal(tmp)^;
  n:=(((SectorsCount div SECTORS_ATLAS_ROW_WIDTH)*SECTORS_ATLAS_WIDTH+(SectorsCount mod SECTORS_ATLAS_ROW_WIDTH)) shl 6)+63;
  for y:=0 to 63 do
  begin
    for x:=0 to 63 do
    begin
      j:=PCardinal(p)^;
      case j shr 28 of
        TIG_ART_TYPE_TILE:begin
                          k:=GetTileName(j);
                          m:=TerrainTileIdListLen;
                          repeat
                            dec(m);
                          until (TerrainTileIdList[m]=k)or(m=0);
                          if TerrainTileIdList[m]=k then
                            SectorsAtlas[n]:=m+(j shl 31)
                          else
                            SectorsAtlas[n]:=TerrainTilesCount-1;
                          end;
      TIG_ART_TYPE_FACADE:begin
                          {k:=(j shr 17)and 255;
                          if j and (1 shl 27)>0 then
                            inc(k,256); }
                          k:=((j shr 17)and 255)+((j and (1 shl 27))shr 19);
                          SectorsAtlas[n]:=FacadesIndex[k]+((j shr 1)and 1023);//+((not(j shl 6))and $80000000);
                          end;
      end;
      inc(p,4);
      dec(n);
    end;
    inc(n,SECTORS_ATLAS_WIDTH+64);
  end;
  VirtualFree(tmp,0,MEM_RELEASE);
  inc(SectorsCount);
end;

function CompileShader(_program,ShaderType: dword; ShaderCode,ShaderName: PAnsiChar): dword;
var
  buf:  array[0..2048] of AnsiChar;
  buf2: array[0..63] of AnsiChar;
  i:    dword;
begin
  result:=glCreateShader(ShaderType);
  glShaderSource(result,1,@ShaderCode,0);
  glCompileShader(result);
  glGetShaderiv(result,GL_COMPILE_STATUS,@i);
  if i=0 then
  begin
    glGetShaderInfoLog(result,sizeof(buf),@i,@buf);
    buf2[wsprintfA(buf2,'ќшибка компил€ции шейдера %s',ShaderName)]:=#0;
    MessageBoxA(0,@buf,@buf2,0);
    ExitProcess(0);
  end;
  glAttachShader(_program,result);
  glDeleteShader(result);
end;

const //sin/cos override for circles generator
  sin: array[0..15] of single=(0.0000,0.3827,0.7071,0.9239,1.0000,0.9239,0.7071,0.3827,-0.0000,-0.3827,-0.7071,-0.9239,-1.0000,-0.9239,-0.7071,-0.3827);
  cos: array[0..15] of single=(1.0000,0.9239,0.7071,0.3827,-0.0000,-0.3827,-0.7071,-0.9239,-1.0000,-0.9239,-0.7071,-0.3827,0.0000,0.3827,0.7071,0.9239);

begin
  i:=GetSystemMetrics(SM_CXSCREEN) shr 1;
  j:=GetSystemMetrics(SM_CYSCREEN) shr 1;
  wnd:=CreateWindowExW(0,'STATIC',0,WS_VISIBLE+WS_OVERLAPPEDWINDOW,0,0,i,j,0,0,0,0);
  GetWindowRect(wnd,ClientRect);
  UIScale:=i/960;
  MoveWindow(wnd,i-(ClientRect.Right shr 1),j-(ClientRect.Bottom shr 1),i,j,false);

  DC:=LoadIconW($400000,PWideChar(1));
  SendMessageW(Wnd,WM_SETICON,0,DC);
  DeleteObject(DC);
  wglMakeCurrent(0,0);
  DC:=GetDC(wnd);
  SelectObject(DC,CreateFontA(round(24*UIScale),round(10*UIScale),0,0,FW_HEAVY,0,0,0,RUSSIAN_CHARSET,OUT_TT_PRECIS,0,PROOF_QUALITY,DEFAULT_PITCH,'Arial'));
  SetPixelFormat(DC,ChoosePixelFormat(DC,@pfd),@pfd);
  RC:=wglCreateContext(DC);
  wglMakeCurrent(DC,RC);
  glLineWidth(4);
  glClearColor(0,0,0,255);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA);
  glPixelStorei(GL_UNPACK_ALIGNMENT,1);
  wglUseFontBitmapsA(DC,0,256,0);
  glGenLists(2);
  glNewList(257,GL_COMPILE);
  glColor4f(0,0,0,0.5);
  glBegin(GL_TRIANGLE_FAN);
  glVertex2f(0,120*UIScale);
  glVertex2f(0,0);
  glVertex2f(500*UIScale,0);
  glVertex2f(500*UIScale,120*UIScale);
  glEnd;
  glEndList;
  glGenTextures(3,@Tex);

  //ReadOpenGLCore;
  glActiveTexture:=wglGetProcAddress('glActiveTexture');
  glCreateProgram:=wglGetProcAddress('glCreateProgram');
  glLinkProgram:=wglGetProcAddress('glLinkProgram');
  glGetUniformLocation:=wglGetProcAddress('glGetUniformLocation');
  glUniform2f:=wglGetProcAddress('glUniform2f');
  glUniform4f:=wglGetProcAddress('glUniform4f');
  glUniform1i:=wglGetProcAddress('glUniform1i');
  glShaderSource:=wglGetProcAddress('glShaderSource');
  glUseProgram:=wglGetProcAddress('glUseProgram');
  glCreateShader:=wglGetProcAddress('glCreateShader');
  glCompileShader:=wglGetProcAddress('glCompileShader');
  glGetShaderiv:=wglGetProcAddress('glGetShaderiv');
  glGetShaderInfoLog:=wglGetProcAddress('glGetShaderInfoLog');
  glAttachShader:=wglGetProcAddress('glAttachShader');
  glDeleteShader:=wglGetProcAddress('glDeleteShader');

  ShaderProgram:=glCreateProgram;
  CompileShader(ShaderProgram,GL_VERTEX_SHADER,VertexShader,'VertexShader');
  CompileShader(ShaderProgram,GL_FRAGMENT_SHADER,FragmentShader,'FragmentShader');
  glLinkProgram(ShaderProgram);
  uScreenSize:=glGetUniformLocation(ShaderProgram,'ScreenSize');
  uParams:=glGetUniformLocation(ShaderProgram,'Params');
  uTileAtlas:=glGetUniformLocation(shaderProgram,'TileAtlas');
  uSectorMap:=glGetUniformLocation(shaderProgram,'SectorsMap');
  uSectorAtlas:=glGetUniformLocation(shaderProgram,'SectorsAtlas');

////////////////////////////////////////////////////////////////////////////////////////////////////
//Loading main module file, all patches and all arcanum*.dat files
/////////////////////////////////////////////////////////////////////////////////////////////////////
  LoadModule('modules\Arcanum.dat');

/////////////////////////////////////////////////////////////////////////////////////////////////////
//Loading tile names
/////////////////////////////////////////////////////////////////////////////////////////////////////
  tmp:=GetFileData('art\tile\tilename.mes',k);
  i:=0;
  LocationsCount:=0;
  repeat
    if tmp[i]='{' then
    begin
      inc(i);
      val(PAnsiChar(@tmp[i]),j,n);
      inc(i,n);
      while tmp[i-1]<>'{' do
        inc(i);
      if j>=400 then
        break;
      case j of
        0:TileTypesOfs[3]:=TileNamesCount;  //Outdoor flipable
      100:TileTypesOfs[2]:=TileNamesCount;  //Outdoor non-flipable
      200:TileTypesOfs[1]:=TileNamesCount;  //Indoor flipable
      300:TileTypesOfs[0]:=TileNamesCount;  //Indoor non-flipable
      end;
      TileNames[TileNamesCount]:=(PCardinal(@tmp[i])^ and $FFFFFF) or $202020;
      inc(TileNamesCount);
    end;
    repeat
      inc(i);
    until (tmp[i-1]=#10)or(i=k);
  until i=k;
  TileNames[TileNamesCount]:=$657362;//'bse'
  inc(TileNamesCount);
  VirtualFree(tmp,0,MEM_RELEASE);

/////////////////////////////////////////////////////////////////////////////////////////////////////
//loading tiles in atlas
/////////////////////////////////////////////////////////////////////////////////////////////////////
  TerrainAtlas:=VirtualAlloc(0,TILES_ATLAS_WIDTH*TILES_ATLAS_WIDTH*3,MEM_COMMIT,PAGE_READWRITE);
  for i:=FATLen-1 downto 0 do
    with FAT[i] do
      if StrCmp(filename,'art\tile\',9)and((pcardinal(@filename[pcardinal(@filename[-4])^-5])^ or $20202000)=$7472612E{'.art'}) then
      begin
        AddArtToAtlas(filename);
        x:=(PCardinal(filename+PCardinal(filename-4)^-13)^ and $FFFFFF)or $202020;
        y:=(PCardinal(filename+PCardinal(filename-4)^-10)^ and $FFFFFF)or $202020;
        for j:=TileNamesCount-1 downto 0 do
          if TileNames[j]=x then
            x:=j
          else if TileNames[j]=y then
            y:=j;
        TerrainTileIdList[TerrainTilesCount-1]:=(x shl 24)+(y shl 16)+(pbyte(filename+PCardinal(filename-4)^-7)^ shl 8)+pbyte(filename+PCardinal(filename-4)^-6)^;
      end;
  TerrainTileIdListLen:=TerrainTilesCount;

/////////////////////////////////////////////////////////////////////////////////////////////////////
//loading facades in atlas
/////////////////////////////////////////////////////////////////////////////////////////////////////
  tmp:=GetFileData('art\facade\facadename.mes',k);
  i:=0;
  repeat
    if tmp[i]='{' then
    begin
      inc(i);
      val(PAnsiChar(@tmp[i]),j,n);
      FacadesIndex[j]:=TerrainTilesCount;
      inc(i,n);
      while tmp[i-1]<>'{' do
        inc(i);
      lstrcpyA(@Buf,'art\facade\');
      j:=11;
      repeat
        Buf[j]:=tmp[i];
        inc(j);
        inc(i);
      until tmp[i]='}';
      PCardinal(@Buf[j])^:=$5452412E;//'.ART'
      Buf[j+4]:=#0;
      AddArtToAtlas(Buf);
      inc(FacadesCount);
    end;
    j:=11;
    repeat
      inc(i);
    until (tmp[i-1]=#10)or(i=k);
  until i=k;
  VirtualFree(tmp,0,MEM_RELEASE);

  AddArtToAtlas('art\tile\ILLbse0a.art');  //last tile for illegal tiles indication

  glActiveTexture(GL_TEXTURE2);
  glBindTexture(GL_TEXTURE_2D,Tex.TileAtlas);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);
  glTexImage2D(GL_TEXTURE_2D,0,{GL_COMPRESSED_RGB_ARB}3,TILES_ATLAS_WIDTH,TILES_ATLAS_WIDTH,0,GL_BGR,GL_UNSIGNED_BYTE,TerrainAtlas);
  VirtualFree(TerrainAtlas,0,MEM_RELEASE); 

////////////////////////////////////////////////////////////////////////////////////////////////////
//Loading Terrain colors
/////////////////////////////////////////////////////////////////////////////////////////////////////
  tmp:=GetFileData('terrain\terrain.mes',k);
  i:=0;
  x:=0;
  y:=0;
  repeat
    if tmp[i]='{' then
    begin
      val(PAnsiChar(@tmp[i+1]),j,n);
      if j<100 then
      begin
        inc(i);
        repeat
          inc(i);
        until tmp[i-1]='{';
        j:=0;
        repeat
          TerrainNames[y][j]:=tmp[i];
          inc(i);
          inc(j);
        until (tmp[i]='/')or(tmp[i]='}');
        while TerrainNames[y][j-1]=' ' do
          dec(j);
        TerrainNames[y][j]:=#0;
        inc(y);
      end
      else if j<201 then
      begin
        inc(i);
        repeat
          inc(i);
        until tmp[i-1]='{';
        with TerrainColors[x] do
        begin
          val(PAnsiChar(@tmp[i]),r,n);
          inc(i,n);
          val(PAnsiChar(@tmp[i]),g,n);
          inc(i,n);
          val(PAnsiChar(@tmp[i+n]),b,n);
          a:=127;
          inc(x);
        end;
      end;
    end;
    repeat
      inc(i);
    until (tmp[i-1]=#10)or(i=k);
  until i=k;
  VirtualFree(tmp,0,MEM_RELEASE);

/////////////////////////////////////////////////////////////////////////////////////////////////////
//Loading WorldMap terrain data
/////////////////////////////////////////////////////////////////////////////////////////////////////
  tmp:=GetFileData('Rules\MapList.mes',k);
  Pint64(@WorldMapPath)^:=397073736045;//'maps\'
  i:=0;
  repeat
    inc(i);
  until StrCmp(@tmp[i],'Type: START_MAP',15);
  repeat
    dec(i);
  until tmp[i-1]='{';
  WorldMapPathLen:=5;
  repeat
    WorldMapPath[WorldMapPathLen]:=tmp[i];
    inc(i);
    inc(WorldMapPathLen);
  until tmp[i]=',';
  WorldMapPath[WorldMapPathLen]:='\';
  inc(WorldMapPathLen);
  VirtualFree(tmp,0,MEM_RELEASE);

  lstrcpyA(@WorldMapPath[WorldMapPathLen],'terrain.tdf');
  tmp:=GetFileData(WorldMapPath,k);
  WorldMapWidth :=PTerrainHeader(tmp).width;
  WorldMapHeight:=PTerrainHeader(tmp).Height;
  WorldMapSize  :=WorldMapWidth*WorldMapHeight;
  if k<WorldMapSize*2+sizeof(TTerrainHeader) then
  begin
    WorldMapTerrain:=VirtualAlloc(0,WorldMapSize shl 1,MEM_COMMIT,PAGE_READWRITE);
    i:=0;
    p:=pointer(tmp+sizeof(TTerrainHeader)+4);
    k:=WorldMapWidth shr 1;
    repeat
      Deflate(p,@WorldMapTerrain[i]);
      m:=i+k-1;
      n:=m;
      repeat  //mirroring terrain map by x-axis
        inc(n);
        dec(m);
        exchangew(WorldMapTerrain[m],WorldMapTerrain[n]);
      until m=i;
      inc(p,pcardinal(p-4)^+4);
      inc(i,WorldMapWidth);
    until i=WorldMapSize;
  end
  else
    WorldMapTerrain:=pointer(tmp+sizeof(TTerrainHeader));

/////////////////////////////////////////////////////////////////////////////////////////////////////
//Building sectors map and sectors atlas
/////////////////////////////////////////////////////////////////////////////////////////////////////
  SectorsColors:=VirtualAlloc(0,WorldMapSize shl 2,MEM_COMMIT,PAGE_READWRITE);
  SectorsMap   :=VirtualAlloc(0,SECTORS_MAP_WIDTH*SECTORS_MAP_WIDTH shl 1,MEM_COMMIT,PAGE_READWRITE);
  SectorsAtlas :=VirtualAlloc(0,SECTORS_ATLAS_WIDTH*SECTORS_ATLAS_WIDTH shl 2,MEM_COMMIT,PAGE_READWRITE);
  for i:=FATLen-1 downto 0 do
    with FAT[i] do
      if StrCmp(filename,WorldMapPath,WorldMapPathLen)and((pcardinal(@filename[pcardinal(@filename[-4])^-5])^ xor $6365732E{'.sec'})and(not $20202020)=0) then
      begin
        val(PAnsiChar(@filename[WorldMapPathLen]),secid,j);
        x:=WorldMapWidth-(secid and $3FFFFFF)-2; //WTF? why 2?
        y:=(secid shr 26) and $3FFFFFF;
        SectorsColors[y*WorldMapWidth+x]:=$7F00FF00;
        SectorsMap[y*SECTORS_MAP_WIDTH+x]:=SectorsCount;
        AddSecToAtlas(filename);
      end;
  RandomSectorsOfs:=SectorsCount;
  for y:=0 to WorldMapHeight-1 do
    for x:=0 to WorldMapWidth-1 do
    begin
      k:=y*WorldMapWidth+x;
      if SectorsColors[k]<>$7F00FF00 then
      begin
        n:=WorldMapTerrain[k];
        for i:=RandomSectorsCount-1 downto 0 do
          if RandomSectors[i]=n then
          begin
            SectorsMap[y*SECTORS_MAP_WIDTH+x]:=RandomSectorsOfs+i;
            goto SectorLoaded;
          end;
        RandomSectors[RandomSectorsCount]:=n;
        SectorsMap[y*SECTORS_MAP_WIDTH+x]:=SectorsCount;
        GetSectorFilename(x,y,@Buf);
        AddSecToAtlas(@Buf);
        inc(RandomSectorsCount);
        SectorLoaded:
      end;  
    end;   
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D,Tex.SectorsMap);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);
  glTexImage2D(GL_TEXTURE_2D,0,GL_R16UI,SECTORS_MAP_WIDTH,SECTORS_MAP_WIDTH,0,GL_RED_INTEGER,GL_UNSIGNED_SHORT,SectorsMap);
  VirtualFree(SectorsMap,0,MEM_RELEASE);
  glActiveTexture(GL_TEXTURE1);
  glBindTexture(GL_TEXTURE_2D,Tex.SectorsAtlas);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_NEAREST);
  glTexImage2D(GL_TEXTURE_2D,0,GL_R32UI,SECTORS_ATLAS_WIDTH,SECTORS_ATLAS_WIDTH,0,GL_RED_INTEGER,GL_UNSIGNED_INT,SectorsAtlas);
  VirtualFree(SectorsAtlas,0,MEM_RELEASE);

/////////////////////////////////////////////////////////////////////////////////////////////////////
//Building points of interest list
/////////////////////////////////////////////////////////////////////////////////////////////////////
  front:=VirtualAlloc(0,4096*4*2,MEM_COMMIT,PAGE_READWRITE);
  front1:=front;
  front2:=@front^[4096];
  way[0]:=-PTerrainHeader(tmp).width;
  way[1]:=1;
  way[2]:=PTerrainHeader(tmp).width;
  way[3]:=-1;
  glNewList(256,GL_COMPILE);
  glColor3f(1,0,0);
  for i:=WorldMapSize-1 downto 0 do
    if SectorsColors[i]=$7F00FF00 then
    begin
      x:=i mod WorldMapWidth;
      y:=i div WorldMapWidth;
      ClientRect.Left:=x;
      ClientRect.Top:=y;
      ClientRect.Right:=x;
      ClientRect.Bottom:=y;
      front1[0]:=i;
      SectorsColors[i]:=SectorsColors[i] or $80000000;
      front1len:=1;
      repeat
        front2len:=0;
        for j:=front1len-1 downto 0 do
          for k:=0 to 3 do
          begin
            m:=front1^[j]+way[k];
            if SectorsColors[m]=$7F00FF00 then
            begin
              x:=m mod WorldMapWidth;
              y:=m div WorldMapWidth;
              if ClientRect.Left>x then
                ClientRect.Left:=x;
              if ClientRect.Top>y then
                ClientRect.Top:=y;
              if ClientRect.Right<x then
                ClientRect.Right:=x;
              if ClientRect.Bottom<y then
                ClientRect.Bottom:=y;
              front2^[front2len]:=m;
              SectorsColors[m]:=SectorsColors[m] or $80000000;
              inc(front2len);
            end;
          end;
        exchange(front1,front2);
        exchange(front1len,front2len);
      until front1len=0;
      m:=ClientRect.Right -ClientRect.Left;
      n:=ClientRect.Bottom-ClientRect.Top;
      k:=round(sqrt(m*m+n*n)+0.5);
      if k<4 then
        k:=4;
      m:=ClientRect.Left+(m shr 1);
      n:=ClientRect.Top +(n shr 1);
      glBegin(GL_LINE_LOOP);
      for j:=0 to 15 do
        glVertex2f(m+sin[j]*k,n+cos[j]*k);
      glEnd;
   end;
  glEndList;
  VirtualFree(front,0,MEM_DECOMMIT);
  
/////////////////////////////////////////////////////////////////////////////////////////////////////
//Painting map according to terrain types
/////////////////////////////////////////////////////////////////////////////////////////////////////
  for i:=WorldMapSize-1 downto 0 do
    if SectorsColors[i]=0 then
      SectorsColors[i]:=TerrainColors[(WorldMapTerrain[i] shr 11)].value;
  VirtualFree(tmp,0,MEM_RELEASE);

/////////////////////////////////////////////////////////////////////////////////////////////////////
//Loading WorldMap bitmaps
/////////////////////////////////////////////////////////////////////////////////////////////////////
  tmp:=GetFileData('WorldMap\WorldMap.mes',k);
  i:=0;
  lstrcpyA(@buf,'WorldMap\');
  repeat
    if tmp[i]='{' then
    begin
      val(PAnsiChar(@tmp[i+1]),j,n);
      if j=50 then
      begin
        inc(i);
        repeat
          inc(i);
        until tmp[i-1]='{';
        val(PAnsiChar(@tmp[i]),WorldMapHTiles,n);
        inc(i,n);
        val(PAnsiChar(@tmp[i]),WorldMapVTiles,n);
        inc(i,n);
        while tmp[i]=' ' do
          inc(i);
        j:=9;
        repeat
          buf[j]:=tmp[i];
          inc(j);
          inc(i);
        until tmp[i]=',';
        p:=@buf[j];
        PCardinal(p+3)^:=1886216750;//'.bmp'
        p[7]:=#0;
        break;
      end;
    end;
    repeat
      inc(i);
    until (tmp[i-1]=#10)or(i=k);
  until i=k;
  VirtualFree(tmp,0,MEM_RELEASE);

  WorldMapRaster:=VirtualAlloc(0,WorldMapSize shl 2,MEM_COMMIT,PAGE_READWRITE);
  WorldMapTileWidth:=WorldMapWidth div WorldMapHTiles;
  WorldMapTileHeight:=WorldMapHeight div WorldMapVTiles;
  WorldMapTileRowSize:=WorldMapWidth*WorldMapTileHeight;
  Align:=((WorldMapTileWidth+3)and -4)-WorldMapTileWidth;
  k:=WorldMapVTiles*WorldMapHTiles;
  m:=WorldMapSize+WorldMapWidth-WorldMapTileWidth;
  for j:=WorldMapVTiles-1 downto 0 do
  begin
    for i:=WorldMapHTiles-1 downto 0 do
    begin
      p[wsprintfA(p,'%03i',k)]:='.';
      tmp:=GetFileData(buf,n);
      pal:=pointer(tmp+sizeof(BITMAPFILEHEADER)+PBITMAPINFO(tmp+sizeof(BITMAPFILEHEADER))^.bmiHeader.biSize);
      n:=PBITMAPFILEHEADER(tmp)^.bfOffBits;
      for y:=WorldMapTileHeight-1 downto 0 do
      begin
        dec(m,WorldMapWidth);
        for x:=WorldMapTileWidth-1 downto 0 do
        begin
          WorldMapRaster[m]:=pal[ord(tmp[n])] or $FF000000;
          inc(n);
          inc(m);
        end;
        inc(n,Align);
        dec(m,WorldMapTileWidth);
      end;
      inc(m,WorldMapTileRowSize-WorldMapTileWidth);
      VirtualFree(tmp,0,MEM_RELEASE);
      dec(k);
    end;
    dec(m,WorldMapTileRowSize-WorldMapWidth);
  end;

/////////////////////////////////////////////////////////////////////////////////////////////////////
//Loading locations
/////////////////////////////////////////////////////////////////////////////////////////////////////
  tmp:=GetFileData('mes\gamearea.mes',k);
  i:=0;
  LocationsCount:=0;
  repeat
    if tmp[i]='{' then
    begin
      inc(i);
      repeat
        inc(i);
      until tmp[i-1]='{';
      with Locations[LocationsCount] do
      begin
        val(PAnsiChar(@tmp[i]),x,n);
        inc(i,n);
        val(PAnsiChar(@tmp[i]),y,n);
        inc(i,n);
        x:=WorldMapWidth-(x shr 6);
        y:=y shr 6;
        while tmp[i-1]<>'/' do
          inc(i);
        namelen:=0;
        repeat
          name[namelen]:=tmp[i];
          inc(namelen);
          inc(i);
        until tmp[i]='/';
        if y>0 then
          inc(LocationsCount);
      end;
    end;
    repeat
      inc(i);
    until (tmp[i-1]=#10)or(i=k);
  until i=k;
  VirtualFree(tmp,0,MEM_RELEASE);

  CloseHandles;
  x:=0;
  y:=0;
  WndProc(wnd,WM_SIZE,0,0);
  SetWindowLongW(wnd,GWL_WNDPROC,LongInt(@WndProc));

  repeat
    GetMessageW(msg,wnd,0,0);
    DispatchMessageW(msg);
  until false;
end.
