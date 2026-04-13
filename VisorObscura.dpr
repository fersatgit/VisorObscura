//Writed in Delphi 7
//To compile from IDE press Ctrl+F9
//This is not a unit but a program. This hack reduses output file size.
//program PoleWin32;
unit VisorObscura;
{$IMAGEBASE $400000}{$E .exe}{$G-}{$R-}{$I-}{$M-}{$Y-}{$D-}{$C-}{$L-}{$Q-}{$O+}
interface
implementation
{$R 1.res}

uses
  Windows,Messages,FileSystem,OpenGL;

type
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
  p:                                                        PAnsiChar;
  tmp:                                                      PAnsiChar;
  pal:                                                      pdword;
  i,j,k,m,n:                                                dword;
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
  WorldMapWidth,WorldMapHeight,WorldMapSize:                dword;
  
  WorldMapPathLen:      dword;
  WorldMapPath:         array[0..255] of AnsiChar;
  buf:                  array[0..255] of AnsiChar;
  WorldMapRaster,Raster: pdword;
  WorldMapTerrain:      pword;
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
  way:                  array[0..3] of integer;

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

function WndProc(wnd,msg,wParam,lParam: dword): dword;stdcall;
label
  redraw;
const
  qword_5B9968: array[0..15] of integer=(-1,1,(2 shl 26)+1,(1 shl 26)+1,(2 shl 26)+3,0,(2 shl 26)+2,-1,3,2,-1,-1,(1 shl 26)+3,-1,-1,-1);
var
  w,h:     integer;
  _x,_y,u: single;
  SecName: array[0..31] of AnsiChar;
  SecPath: array[0..255] of AnsiChar;
  SecId:   int64;
begin
  case msg of
  WM_ERASEBKGND:;
       WM_PAINT:begin
         redraw:_x:=WorldMapXPos*Scale;
                _y:=WorldMapYPos*Scale;
                glClear(GL_COLOR_BUFFER_BIT);

                //WorldMap
                glLoadIdentity;
                glTranslatef(-1,1,0);
                glPixelZoom(Scale,-Scale);
                glRasterPos2f(0,0);
                glBitmap(0,0,0,0,_x,-_y,0);
                glDrawPixels(WorldMapWidth,WorldMapHeight,GL_BGRA,GL_UNSIGNED_BYTE,WorldMapRaster);

                //Terrain (sectors)
                glDrawPixels(WorldMapWidth,WorldMapHeight,GL_RGBA,GL_UNSIGNED_BYTE,Raster);

                //Circles around points of interest
                glLoadMatrixf(@ScaledMatrix);
                glTranslatef(WorldMapXPos,WorldMapYPos,0);
                glCallList(256);

                //Location names
                glColor3f(1,1,1);
                glLoadIdentity;
                glTranslatef(-1,1,0);
                for w:=LocationsCount-1 downto 0 do
                  with Locations[w] do
                  begin
                    glRasterPos2f(0,0);
                    glBitmap(0,0,0,0,x*Scale+_x,-y*Scale-_y,0);
                    glCallLists(namelen,GL_UNSIGNED_BYTE,@name);
                  end;

                //Sector info  
                glLoadMatrixf(@matrix);
                glCallList(257);
                glColor3f(1,1,0);
                w:=trunc(Mouse.x/Scale-WorldMapXPos);
                h:=trunc(Mouse.y/Scale-WorldMapYPos);
                glRasterPos2f(0,20);
                glCallLists(wsprintfA(@buf,'Coords: %i,%i',WorldMapWidth-w,h),GL_UNSIGNED_BYTE,@buf);
                if (w>=0)and(w<=WorldMapWidth)and(h>=0)and(h<=WorldMapHeight) then
                begin
                  i:=WorldMapTerrain[k] shr 11;
                  j:=(WorldMapTerrain[k] shr 6) and 31;
                  k:=h*WorldMapWidth+w;
                  if Raster[k]=$FF00FF00 then
                  begin
                    move(WorldMapPath,SecPath,WorldMapPathLen);
                    SecPath[WorldMapPathLen]:=#0;
                    SecId:=int64((int64(h) shl 26)+WorldMapWidth-w)
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
                  glRasterPos2f(0,50*UIScale);
                  glCallLists(wsprintfA(@buf,'%s\%s.sec',@SecPath,@SecName),GL_UNSIGNED_BYTE,@buf);
                  glRasterPos2f(0,80*UIScale);
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
                if (Scale*u>8)or(Scale*u<0.1) then
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
                goto redraw;
                end;
       WM_CLOSE:ExitProcess(0);
  else
    result:=DefWindowProcW(wnd,msg,wParam,lParam);
  end;
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

////////////////////////////////////////////////////////////////////////////////////////////////////
//Loading main modula file, all patches and all arcanum*.dat files
/////////////////////////////////////////////////////////////////////////////////////////////////////
  LoadModule('modules\Arcanum.dat');

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
//Building sectors map
/////////////////////////////////////////////////////////////////////////////////////////////////////
  Raster:=VirtualAlloc(0,WorldMapSize shl 2,MEM_COMMIT,PAGE_READWRITE);
  for i:=FATLen-1 downto 0 do
    with FAT[i] do
      if StrCmp(filename,WorldMapPath,WorldMapPathLen)and(pcardinal(@filename[pcardinal(@filename[-4])^-5])^=$6365732E{'.sec'}) then
      begin
        val(PAnsiChar(@filename[WorldMapPathLen]),secid,j);
        Raster[(((secid shr 26) and $3FFFFFF)*WorldMapWidth+WorldMapWidth-(secid and $3FFFFFF))]:=$7F00FF00;
      end;

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
    if Raster[i]=$7F00FF00 then
    begin
      x:=i mod WorldMapWidth;
      y:=i div WorldMapWidth;
      ClientRect.Left:=x;
      ClientRect.Top:=y;
      ClientRect.Right:=x;
      ClientRect.Bottom:=y;
      front1[0]:=i;
      Raster[i]:=Raster[i] or $80000000;
      front1len:=1;
      repeat
        front2len:=0;
        for j:=front1len-1 downto 0 do
          for k:=0 to 3 do
          begin
            m:=front1^[j]+way[k];
            if Raster[m]=$7F00FF00 then
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
              Raster[m]:=Raster[m] or $80000000;
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
  begin
    if Raster[i]=0 then
      Raster[i]:=TerrainColors[(WorldMapTerrain[i] shr 11)].value;
  end;
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
