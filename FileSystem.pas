unit FileSystem;
interface

uses
  Windows;

function  wsprintfA(buf,fmt: PAnsiChar):dword;cdecl;varargs;external user32;
function  Deflate(indata, outdata: pointer): Cardinal;
function  StrCmp(str1,str2:PAnsiChar; len: dword): boolean;
function  GetFileData(name:PAnsiChar;out size: dword;mandatory: boolean=true):pointer;
procedure LoadModule(filename: PWideChar);
procedure CloseHandles;

type
  TDirEntry =packed record
             FileName:   PansiChar;
             Flags:      dword;
             UncompSize: dword;
             CompSize:   dword;
             Offset:     dword;
             end;
  TFATEntry =packed record
             filename: PAnsiChar;
             DirEntry: ^TDirEntry;
             map:      PAnsiChar;
             end;
  TFATEntryArr=array[0..0] of TFATEntry;
  PFATEntry=^TFATEntryArr;

var
  FATLen: dword;
  FAT:    PFATEntry;

implementation

var
  OpenedFilesCount: dword;
  OpenedFiles:      array[0..31] of packed record
                                    FileHandle,FileMap: THandle;
                                    View,Dir:           PAnsiChar;
                                    DirEntryCount:      dword;
                                    end;

function OpenFile(filename: PWideChar): boolean;
type
  TDATFooter=packed record
             ModuleID:     TGUID;
             mark:         dword;
             NamePoolSize: dword;
             DictSize:     dword;
             end;
  PDATFooter=^TDATFooter;
var
  fsize:   dword;
  FileEnd: PAnsiChar;
begin
  result:=false;
  with OpenedFiles[OpenedFilesCount] do
  begin
    FileHandle   :=CreateFileW(filename,GENERIC_READ,0,0,OPEN_EXISTING,0,0);
    if FileHandle=INVALID_HANDLE_VALUE then
      exit;
    fSize        :=GetFileSize(FileHandle,0);
    FileMap      :=CreateFileMappingW(FileHandle,0,PAGE_READONLY,0,0,0,);
    View         :=MapViewOfFile(FileMap,FILE_MAP_READ,0,0,0);
    FileEnd      :=pointer(View+fSize);
    Dir          :=pointer(FileEnd-PDATFooter(FileEnd-sizeof(TDatFooter))^.DictSize);
    DirEntryCount:=PCardinal(Dir)^;
    inc(FATLen,DirEntryCount);
    inc(Dir,4);
    inc(OpenedFilesCount);
  end;
  result:=true;
end;

procedure LoadModule(filename: PWideChar);
var
  i,j,k:        integer;
  CurEntry:     PAnsiChar;
  Buf:          array[0..MAX_PATH-1] of WideChar;
  FindData:     WIN32_FIND_DATAW;
  SearchHandle: THandle;
  PathLen:      dword;
begin
  FATLen:=0;
  if OpenFile(filename)=false then
  begin
    MessageBoxW(0,'Файл "module\arcanum.dat" не найден.',0,0);
    ExitProcess(0);
  end;

  k:=lstrlenW(filename)-3;
  move(filename^,Buf,k shl 1);
  lstrcpyW(@Buf[k],'patch0');
  inc(k,5);
  repeat //GetFileData searches from end of FAT towards begining, so patches will override existing files
    Buf[k]:=WideChar(i+ord('0'));
  until OpenFile(@Buf)=false;

  GetCurrentDirectoryW(length(Buf),@Buf);
  lstrcatW(@Buf,'\arcanum*.dat');
  SearchHandle:=FindFirstFileW(@Buf,FindData);
  if SearchHandle<>INVALID_HANDLE_VALUE then
  begin
    OpenFile(@FindData.cFileName);
    while FindNextFileW(SearchHandle,FindData) do
      OpenFile(@FindData.cFileName);
    FindClose(SearchHandle);
  end;

  FAT:=VirtualAlloc(0,FATLen*sizeof(TFATEntry),MEM_COMMIT,PAGE_READWRITE);

  k:=0;
  for i:=0 to OpenedFilesCount-1 do
    with OpenedFiles[i] do
    begin
      CurEntry:=Dir;
      for j:=DirEntryCount-1 downto 0 do
        with FAT[k] do
        begin
          filename:=@CurEntry[4];
          DirEntry:=@CurEntry[PCardinal(CurEntry)^+4];
          CurEntry:=@PAnsiChar(DirEntry)[sizeof(TDirEntry)];
          Map:=View;
          inc(k);
        end;
    end;
end;

procedure CloseHandles;
var
  i: integer;
begin
  for i:=OpenedFilesCount-1 downto 0 do
    with OpenedFiles[i] do
    begin
      UnmapViewOfFile(View);
      CloseHandle(FileMap);
      CloseHandle(FileHandle);
    end;
  OpenedFilesCount:=0;
end;

function Deflate(indata, outdata: pointer): Cardinal;
type
   HuffTable=       packed record
                    hmax:        array[0..15]    of integer;
                    hvalues:     array[0..32767] of word;
                    hlengths:    array[0..288]   of byte;
                    lencount:    array[0..15]    of word;
                    huffcount:   Cardinal;
                    end;
const
 mask: array[0..15] of Cardinal=($00000000, $00000001, $00000003, $00000007,
                                 $0000000F, $0000001F, $0000003F, $0000007F,
                                 $000000FF, $000001FF, $000003FF, $000007FF,
                                 $00000FFF, $00001FFF, $00003FFF, $00007FFF);
reverse:      array[0..31] of byte=(0,16,8,24,4,20,12,28,2,18,10,26,6,22,14,30,1,17,9,25,5,21,13,29,3,19,11,27,7,23,15,31);
lensequence:  array[0..18] of byte=(16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15);
extralen:     array[0..28] of byte=(0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0);
lenadjust:    array[0..28] of word=(3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258);
extradist:    array[0..29] of byte=(0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13);
distadjust:   array[0..29] of word=(1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577);

static:packed record
       hmax:      array[0..15]  of integer;
       hvalues:   array[0..511] of word;
       end=(hmax:    (0,0,0,0,0,0,0,24,200,512,0,0,0,0,0,0);
            hvalues: (256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   1,   2,   3,   4,   5,   6,   7,   8,   9,  10,  11,  12,  13,  14,  15,
                      16,  17,  18,  19,  20,  21,  22,  23,  24,  25,  26,  27,  28,  29,  30,  31,  32,  33,  34,  35,  36,  37,  38,  39,  40,  41,  42,  43,  44,  45,  46,  47,  48,  49,  50,  51,  52,  53,  54,  55,  56,  57,  58,  59,  60,  61,  62,  63,  64,  65,  66,  67,  68,  69,  70,  71,  72,  73,  74,  75,  76,  77,  78,  79,
                      80,  81,  82,  83,  84,  85,  86,  87,  88,  89,  90,  91,  92,  93,  94,  95,  96,  97,  98,  99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143,
                      280, 281, 282, 283, 284, 285, 286, 287,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
                      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
                      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
                      0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189, 190, 191,
                      192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255));

//sgovno: array[0..10] of byte=(115, 73, 77, 203, 73, 44, 73, 85, 0, 17, 0);
//dgovno: array[0..77] of byte=(12,200,65,10,128,32,16,5,208,125,208,29,254,9,186,132,235,160,43,76,250,181,1,29,33,39,161,219,215,91,190,208,173,220,226,79,21,215,110,3,221,112,50,246,166,86,32,134,61,28,27,142,74,25,252,31,146,166,14,38,248,37,14,230,204,232,58,9,109,141,73,197,89,223,117,249,6,0);
var
  curbit:           Cardinal;
  lastblock:        Cardinal;
  c,d,i,j,k:        Cardinal;
  HLIT,HDIST,HCLEN: Cardinal;
  lit,dist:         HuffTable;
  startdata:        pointer;

  function  sign(x: Cardinal): integer;register;assembler;
  asm
  sar   eax,31
  end;

  procedure move(var source,dest; count: Cardinal);assembler;register;
  asm
    xchg eax,esi
    xchg edx,edi
    rep  movsb
    xchg eax,esi
    xchg edx,edi
  end;

  function HuffRead(var table: HuffTable): Cardinal;
  var
      i,j,k: integer;
  begin
      i:=0;
      j:=Cardinal(indata^) shr curbit;
      k:=0;
      repeat
          i:=(i shl 1)+(j and 1);
          j:=j shr 1;
          inc(k);
      until i<table.hmax[k];
      curbit:=curbit+k;
      inc(Cardinal(indata),curbit shr 3);
      curbit:=curbit and 7;
      result:=table.hvalues[i];
  end;

  procedure MakeHuffTable(var table: HuffTable);
  var
    i,j,k: Cardinal;
  begin
      k:=0;
      table.lencount[0]:=0;
      for i:=1 to 15 do
      begin
          j:=k or sign(table.lencount[i]-1);
          table.hmax[i]:=j;
          k:=(k+table.lencount[i]) shl 1;
      end;
      for i:=0 to table.huffcount-1 do
      begin
          j:=table.hlengths[i];
          if j<>0 then
          begin
              table.hvalues[table.hmax[j]]:=i;
              inc(table.hmax[j]);
          end;
      end;
  end;

  procedure UnpackLen(var outtable,intable: HuffTable);
  var
     i,j,k,l: Cardinal;
  begin
      FillChar(outtable.lencount,sizeof(outtable.lencount),0);   //Распаковка длин алфавита
      i:=0;
      repeat
          l:=HuffRead(intable);
          j:=Cardinal(indata^) shr curbit;
          case l of
          0..15:begin
                c:=1;
                inc(outtable.lencount[l]);
                outtable.hlengths[i]:=l;
                end;
             16:begin
                curbit:=curbit+2;
                c     :=(j and 3)+3;
                l     :=outtable.hlengths[i-1];
                FillChar(outtable.hlengths[i],c,l);
                inc(outtable.lencount[l],c);
                end;
             17:begin
                curbit:=curbit+3;
                c     :=(j and 7)+3;
                FillChar(outtable.hlengths[i],c,0);
                end;
             18:begin
                curbit:=curbit+7;
                c     :=(j and 127)+11;
                FillChar(outtable.hlengths[i],c,0);
                end;
          end;
          i:=i+c;
      until i>=outtable.huffcount;
      inc(Cardinal(indata),curbit shr 3);
      curbit :=curbit and 7;
  end;

begin
    startdata:=outdata;
    if word(indata^) and 8192<>0 then
        inc(Cardinal(indata),4);
    inc(Cardinal(indata),2);

    curbit:=0;
    repeat
        j        :=Cardinal(indata^) shr curbit;
        lastblock:=j and 1;
        curbit   :=curbit+3;
        case (j shr 1)and 3 of
        0:begin
          inc(Cardinal(indata),curbit shr 3);
          curbit :=curbit and 7;
          if curbit<>0 then
          begin
              inc(Cardinal(indata));
              curbit:=0;
          end;
          k:=word(indata^);
          inc(Cardinal(indata),2);
          move(indata^,outdata^,k);
          inc(Cardinal(indata),k);
          inc(Cardinal(outdata),k);
          end;
        1:begin
          repeat
              k:=HuffRead(HuffTable(pointer(@static)^));
              if k<256 then
              begin
                  byte(outdata^):=k;
                  inc(Cardinal(outdata));
              end
              else if k>256 then
              begin
                  i      :=extralen[k-257];
                  j      :=Cardinal(indata^) shr curbit;
                  k      :=(j and mask[i])+lenadjust[k-257];
                  j      :=j shr i;
                  c      :=reverse[j and 31];
                  curbit :=curbit+i+extradist[c]+5;
                  c      :=Cardinal(outdata)-((j shr 5) and mask[extradist[c]])-distadjust[c];
                  inc(Cardinal(indata),curbit shr 3);
                  curbit :=curbit and 7;
                  move(pointer(c)^,outdata^,k);
                  inc(Cardinal(outdata),k);
              end
              else
                  break;
          until false;
          end;
        2:begin
          j             :=Cardinal(indata^) shr curbit;
          HLIT          :=(j and 31)+257;
          dist.huffcount:=((j shr 5) and 31)+1;
          HCLEN         :=((j shr 10) and 15)+4;
          curbit        :=curbit+14;

//Получаем коды Хаффмана для длин алфавита и смещений
          FillChar(lit.hlengths,19,0);
          FillChar(lit.lencount,sizeof(lit.lencount),0);
          for i:=0 to HCLEN-1 do
          begin
              c:=(Cardinal(indata^) shr curbit) and 7;
              lit.hlengths[lensequence[i]]:=c;
              inc(lit.lencount[c]);
              curbit:=curbit+3;
              inc(Cardinal(indata),curbit shr 3);
              curbit:=curbit and 7;
          end;
          lit.huffcount:=19;
          MakeHuffTable(lit);

//Получаем коды хаффмана для алфавита и смещений
          lit.huffcount:=HLIT;
          UnpackLen(lit,lit);
          UnpackLen(dist,lit);
          MakeHuffTable(lit);
          MakeHuffTable(dist);

//Распаковка данных
          repeat
              k:=HuffRead(lit);
              if k<256 then
              begin
                  byte(outdata^):=k;
                  inc(Cardinal(outdata));
              end
              else if k>256 then
              begin
                  j      :=((Cardinal(indata^) shr curbit) and mask[extralen[k-257]])+lenadjust[k-257];
                  curbit :=curbit+extralen[k-257];
                  k      :=HuffRead(dist);
                  c      :=Cardinal(outdata)-((Cardinal(indata^) shr curbit) and mask[extradist[k]])-distadjust[k];
                  curbit :=curbit+extradist[k];
                  inc(Cardinal(indata),curbit shr 3);
                  curbit :=curbit and 7;
                  move(pointer(c)^,outdata^,j);
                  inc(Cardinal(outdata),j);
              end
              else
                  break;
          until false;
          end;
        end;
    until lastblock<>0;
    result:=Cardinal(outdata)-Cardinal(startdata);
end;

function StrCmp(str1,str2:PAnsiChar; len: dword): boolean;
var
  i: dword;
begin
  result:=true;
  for i:=0 to len-1 do
    if (ord(str1[i]) xor ord(str2[i])) and byte(not 32)<>0 then
    begin
      result:=false;
      exit;
    end;
end;

function GetFileData(name:PAnsiChar;out size: dword;mandatory: boolean=true):pointer;
var
  i:   dword;
  Buf: array[0..255] of AnsiChar;
begin
  size:=0;
  result:=0;
  for i:=FATLen-1 downto 0 do
    with FAT[i] do
     if StrCmp(filename,name,pcardinal(@filename[-4])^) then
     begin
       size:=DirEntry^.UncompSize;
       if DirEntry^.Flags and 2>0 then
       begin
         result:=VirtualAlloc(0,size,MEM_COMMIT,PAGE_READWRITE);
         Deflate(pointer(LongInt(map)+DirEntry^.Offset),result);
       end
       else
         result:=pointer(LongInt(map)+DirEntry^.Offset);
       exit;
     end;
  if mandatory then
  begin
    Buf[wsprintfA(@buf,'Файл "%s" не найден в архиве.',name)]:=#0;
    MessageBoxA(0,@Buf,0,0);
    ExitProcess(0);
  end;  
end;

initialization
end.