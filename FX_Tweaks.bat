@echo off
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
start "" powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$bat='%~f0'; try{ $c=[IO.File]::ReadAllText($bat); iex $c.Substring($c.LastIndexOf('#'+'PS#')) }catch{ Add-Type -AssemblyName System.Windows.Forms; [void][Windows.Forms.MessageBox]::Show('FX Tweaks could not start: '+$_.Exception.Message,'FX Tweaks') }"
exit /b
#PS#
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
try{
$FX_VERSION='2026.10.09.1'
$FX_UPDATE_URL='https://raw.githubusercontent.com/haraldrichter12-hub/fx-tweaks/main/FX_Tweaks.bat'
[Windows.Forms.Application]::EnableVisualStyles()
Remove-TypeData System.Array -ErrorAction SilentlyContinue
try{ [Windows.Forms.Application]::SetUnhandledExceptionMode('CatchException') }catch{}
function Get-RemoteVersion($text){ if($text -match "\`$FX_VERSION='([0-9.]+)'"){ $Matches[1] }else{ '' } }
function Ver-Num($v){ $p=($v -split '\.'); $n=0L; foreach($x in $p){ $n=$n*100000+[int64]$x }; $n }
function Check-Update{
  if(-not $bat){ return }
  if((Get-ItemProperty 'HKCU:\Software\FXTweaks' -Name NoAutoUpdate -ErrorAction SilentlyContinue).NoAutoUpdate -eq 1){ return }
  try{
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $wc=New-Object Net.WebClient; $wc.Headers.Add('Cache-Control','no-cache'); $wc.Headers.Add('User-Agent','FXTweaks')
    $remote=$wc.DownloadString($FX_UPDATE_URL + '?t=' + [DateTime]::UtcNow.Ticks)
    $rv=Get-RemoteVersion $remote
    if($rv -and (Ver-Num $rv) -gt (Ver-Num $FX_VERSION)){
      $cur=[IO.File]::ReadAllText($bat)
      if($remote -ne $cur -and $remote -match '#'+'PS#'){
        $tmp="$bat.new"; [IO.File]::WriteAllText($tmp,$remote,(New-Object Text.UTF8Encoding($false)))
        # swap files and relaunch via a tiny helper, then exit this instance
        $vbs=Join-Path $env:TEMP 'fx_update.vbs'
        $q=[char]34
        $lines=@(
          'WScript.Sleep 1200',
          'Set fso=CreateObject("Scripting.FileSystemObject")',
          'On Error Resume Next',
          'fso.DeleteFile ' + $q + $bat + $q + ', True',
          'fso.MoveFile ' + $q + $tmp + $q + ', ' + $q + $bat + $q,
          'Set sh=CreateObject("WScript.Shell")',
          'sh.Run ' + $q + $q + $q + $bat + $q + $q + $q + ', 0, False' )
        [IO.File]::WriteAllLines($vbs,$lines,(New-Object Text.ASCIIEncoding))
        Start-Process 'wscript.exe' -ArgumentList ("$q$vbs$q")
        $script:updating=$true } }
  }catch{}
}
try{ Check-Update }catch{}
if($script:updating){ return }
[Windows.Forms.Application]::add_ThreadException({ param($s,$e)
  try{ "$(Get-Date) $($e.Exception.Message)" | Out-File (Join-Path $env:TEMP 'FXTweaks_error.txt') -Append
    if(-not $script:errShown){ $script:errShown=$true; Log "Something went wrong: $($e.Exception.Message)" $bad } }catch{} })

$cs=@"
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
public struct FXDEVMODE {
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
  public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra; public int dmFields;
  public int dmPositionX; public int dmPositionY; public int dmDisplayOrientation; public int dmDisplayFixedOutput;
  public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
  [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
  public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight; public int dmDisplayFlags; public int dmDisplayFrequency;
  public int dmICMMethod; public int dmICMIntent; public int dmMediaType; public int dmDitherType; public int dmReserved1; public int dmReserved2; public int dmPanningWidth; public int dmPanningHeight;
}
public static class FXNative {
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool EnumDisplaySettings(string dev, int mode, ref FXDEVMODE dm);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int ChangeDisplaySettings(ref FXDEVMODE dm, int flags);
  static FXDEVMODE NewMode(){ FXDEVMODE m = new FXDEVMODE(); m.dmSize = (short)Marshal.SizeOf(typeof(FXDEVMODE)); return m; }
  public static int[] Refresh(){
    FXDEVMODE c = NewMode(); if(!EnumDisplaySettings(null, -1, ref c)) return new int[]{0,0};
    int max = c.dmDisplayFrequency; FXDEVMODE m = NewMode();
    for(int i = 0; EnumDisplaySettings(null, i, ref m); i++){
      if(m.dmPelsWidth == c.dmPelsWidth && m.dmPelsHeight == c.dmPelsHeight && m.dmBitsPerPel == c.dmBitsPerPel && m.dmDisplayFrequency > max) max = m.dmDisplayFrequency; }
    return new int[]{ c.dmDisplayFrequency, max }; }
  public static int SetMaxRefresh(){
    int[] r = Refresh(); if(r[1] <= r[0]) return 0;
    FXDEVMODE c = NewMode(); EnumDisplaySettings(null, -1, ref c);
    c.dmDisplayFrequency = r[1]; c.dmFields = 0x400000; return ChangeDisplaySettings(ref c, 1); }
  [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
  [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr hwnd, string app, string idList);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr hwnd, int msg, IntPtr wp, string lp);
}
"@
if(-not ('FXNative' -as [type])){ try{ Add-Type -TypeDefinition $cs }catch{} }
try{ [void][FXNative]::SetProcessDPIAware() }catch{}
$g0=[Drawing.Graphics]::FromHwnd([IntPtr]::Zero); $S=[math]::Max(1,$g0.DpiX/96); $g0.Dispose()
function Px($v){ [int][math]::Round($v*$S) }

$STEPLOG=Join-Path $env:TEMP 'FXTweaks_startup.txt'
try{ "FX Tweaks startup $(Get-Date)" | Out-File $STEPLOG }catch{}
$splash=New-Object Windows.Forms.Form; $splash.FormBorderStyle='None'; $splash.StartPosition='CenterScreen'; $splash.TopMost=$true
$splash.Size=New-Object Drawing.Size((Px 380),(Px 110)); $splash.BackColor=[Drawing.Color]::FromArgb(23,20,37); $splash.Text='FX Tweaks'
$splashTitle=New-Object Windows.Forms.Label; $splashTitle.Text='FX Tweaks'; $splashTitle.ForeColor=[Drawing.Color]::FromArgb(177,151,252)
$splashTitle.Font=New-Object Drawing.Font('Segoe UI Semibold',16); $splashTitle.AutoSize=$true; $splashTitle.Location=New-Object Drawing.Point((Px 20),(Px 16))
$splashLbl=New-Object Windows.Forms.Label; $splashLbl.Text='Starting...'; $splashLbl.ForeColor=[Drawing.Color]::FromArgb(150,143,176)
$splashLbl.Font=New-Object Drawing.Font('Segoe UI',9.5); $splashLbl.AutoSize=$true; $splashLbl.Location=New-Object Drawing.Point((Px 22),(Px 64))
$splash.Controls.Add($splashTitle); $splash.Controls.Add($splashLbl)
$splash.Show(); $splash.Refresh()
function Step($m){ try{ $splashLbl.Text=$m; $splash.Refresh(); "$(Get-Date -Format 'HH:mm:ss.fff')  $m" | Out-File $STEPLOG -Append }catch{} }
Step 'Loading theme...'

# =========================================================
#  Theme
# =========================================================
function C($r,$g,$b){[Drawing.Color]::FromArgb($r,$g,$b)}
$bg=C 17 15 26      # window background
$sb=C 23 20 37      # sidebar / table headers
$pn=C 31 27 48      # cards, lists, inputs
$hot=C 38 33 59     # row hover
$hv=C 46 40 72      # selected / button hover
$bd=C 58 50 90      # borders and dividers
$pr=C 124 58 237    # primary purple
$prh=C 143 84 245   # primary hover
$prd=C 109 40 217   # primary pressed
$ac=C 177 151 252   # light purple text
$tx=C 236 233 246   # main text
$mu=C 150 143 176   # muted text
$okc=C 52 211 153; $warn=C 240 190 60; $bad=C 240 100 100
$pillOn=C 22 74 58; $pillOff=C 52 46 76
$white=[Drawing.Color]::White

$fUI=New-Object Drawing.Font('Segoe UI',10)
$fBtn=New-Object Drawing.Font('Segoe UI Semibold',9.5)
$fRow=New-Object Drawing.Font('Segoe UI',9.5)
$fHdr=New-Object Drawing.Font('Segoe UI Semibold',9)
$fIcon=New-Object Drawing.Font('Segoe MDL2 Assets',12)
$fPill=New-Object Drawing.Font('Segoe UI Semibold',8)

$script:busy=$false; $script:hotRow=@{}; $script:radius=@{}; $script:themed=@(); $script:brushes=@{}
$rowImgs=New-Object Windows.Forms.ImageList; $rowImgs.ImageSize=New-Object Drawing.Size(1,(Px 32))

# =========================================================
#  Drawing helpers
# =========================================================
function DE{ [Windows.Forms.Application]::DoEvents() }
function Br($c){ $k=$c.ToArgb(); if(-not $script:brushes.ContainsKey($k)){ $script:brushes[$k]=New-Object Drawing.SolidBrush($c) }; $script:brushes[$k] }
function RoundPath($x,$y,$w,$h,$r){
  $p=New-Object Drawing.Drawing2D.GraphicsPath
  $r=[math]::Min([double]$r,[math]::Min([double]$w,[double]$h)/2); $d=[int]($r*2)
  if($d -lt 2){ $p.AddRectangle((New-Object Drawing.Rectangle([int]$x,[int]$y,[int]$w,[int]$h))); return $p }
  $p.AddArc([int]$x,[int]$y,$d,$d,180,90); $p.AddArc([int]($x+$w-$d),[int]$y,$d,$d,270,90)
  $p.AddArc([int]($x+$w-$d),[int]($y+$h-$d),$d,$d,0,90); $p.AddArc([int]$x,[int]($y+$h-$d),$d,$d,90,90)
  $p.CloseFigure(); $p }
function Round($c,$r=8){
  if(-not $script:radius.ContainsKey($c)){
    $c.Add_Paint({ try{
      $g=$_.Graphics; $g.SmoothingMode='AntiAlias'; $w=$this.Width; $h=$this.Height
      $p=New-Object Drawing.Drawing2D.GraphicsPath; $p.FillMode='Alternate'
      $p.AddRectangle((New-Object Drawing.Rectangle(-1,-1,($w+2),($h+2))))
      $p.AddPath((RoundPath 0 0 $w $h $script:radius[$this]),$false)
      $g.FillPath((Br $this.Parent.BackColor),$p); $p.Dispose() }catch{} })
    $c.Add_SizeChanged({ $this.Invalidate() }) }
  $script:radius[$c]=(Px $r); $c.Invalidate() }

# ---------- smooth color fades for hover ----------
$script:bcol=@{}; $script:fadeTo=@{}
function Mix($a,$b,$t){ [Drawing.Color]::FromArgb([int]($a.R+($b.R-$a.R)*$t),[int]($a.G+($b.G-$a.G)*$t),[int]($a.B+($b.B-$a.B)*$t)) }
function Get-Col($c){ if($c -is [Windows.Forms.Button]){ $v=$script:bcol[$c]; if($v){ return $v } }; $c.BackColor }
function Set-Col($c,$col){ if($c -is [Windows.Forms.Button]){ $script:bcol[$c]=$col; $c.Invalidate() }else{ $c.BackColor=$col } }
$fadeTimer=New-Object Windows.Forms.Timer; $fadeTimer.Interval=15
$fadeTimer.Add_Tick({ try{
  foreach($c in @($script:fadeTo.Keys)){
    $to=$script:fadeTo[$c]; $n=Mix (Get-Col $c) $to 0.3
    if(([math]::Abs($n.R-$to.R)+[math]::Abs($n.G-$to.G)+[math]::Abs($n.B-$to.B)) -le 6){ $n=$to; $script:fadeTo.Remove($c) }
    Set-Col $c $n }
  if($script:fadeTo.Count -eq 0){ $fadeTimer.Stop() } }catch{ $fadeTimer.Stop() } })
function Fade-To($c,$col){ $script:fadeTo[$c]=$col; $fadeTimer.Start() }
$dbProp=[Windows.Forms.Control].GetProperty('DoubleBuffered',[Reflection.BindingFlags]'NonPublic,Instance')
function DoubleBuffer($c){ $dbProp.SetValue($c,$true,$null) }
function CRef($c){ [int]$c.R + ([int]$c.G*256) + ([int]$c.B*65536) }
function Dwm($h,$a,$v){ $x=[int]$v; try{ [void][FXNative]::DwmSetWindowAttribute($h,$a,[ref]$x,4) }catch{} }

# ---- "FX" app icon (purple rounded square) ----
function New-FXBitmap($s){
  $bm=New-Object Drawing.Bitmap($s,$s); $g=[Drawing.Graphics]::FromImage($bm)
  $g.SmoothingMode='AntiAlias'; $g.TextRenderingHint='AntiAlias'; $g.Clear([Drawing.Color]::Transparent)
  $r=[math]::Max(2,[int]($s*0.22)); $path=RoundPath 0 0 ($s-1) ($s-1) $r
  # sunset purple: warm coral at the top, orchid in the middle, deep violet at the bottom
  $gb=New-Object Drawing.Drawing2D.LinearGradientBrush((New-Object Drawing.Rectangle(0,0,$s,$s)),(C 255 138 120),(C 92 36 170),([single]90))
  $cbl=New-Object Drawing.Drawing2D.ColorBlend(3)
  $cbl.Colors=[Drawing.Color[]]@((C 255 138 120),(C 214 84 196),(C 92 36 170)); $cbl.Positions=[single[]]@(0,0.5,1)
  $gb.InterpolationColors=$cbl; $g.FillPath($gb,$path); $gb.Dispose()
  $fsz=if($s -le 24){$s*0.52}else{$s*0.44}
  $font=New-Object Drawing.Font('Segoe UI',[single]$fsz,[Drawing.FontStyle]::Bold,[Drawing.GraphicsUnit]::Pixel)
  $sf=New-Object Drawing.StringFormat; $sf.Alignment='Center'; $sf.LineAlignment='Center'
  $g.DrawString('FX',$font,[Drawing.Brushes]::Black,(New-Object Drawing.RectangleF(0,[single]($s*0.03),$s,$s)),$sf)
  $font.Dispose(); $g.Dispose(); $path.Dispose(); $bm }
function Save-FXIco($path){
  $sizes=@(16,24,32,48,256)
  $pngs=foreach($s in $sizes){ $bm=New-FXBitmap $s; $ms=New-Object IO.MemoryStream; $bm.Save($ms,[Drawing.Imaging.ImageFormat]::Png); $bm.Dispose(); ,$ms.ToArray() }
  $fs=[IO.File]::Create($path); $w=New-Object IO.BinaryWriter($fs)
  $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
  $off=6+16*$sizes.Count
  for($i=0;$i -lt $sizes.Count;$i++){
    $d=$pngs[$i]; $b=[byte]$(if($sizes[$i] -ge 256){0}else{$sizes[$i]})
    $w.Write($b); $w.Write($b); $w.Write([byte]0); $w.Write([byte]0)
    $w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$d.Length); $w.Write([uint32]$off); $off+=$d.Length }
  foreach($d in $pngs){ $w.Write([byte[]]$d) }
  $w.Close() }

# =========================================================
#  Form
# =========================================================
Step 'Building the window...'
$f=New-Object Windows.Forms.Form
$f.Text='FX Tweaks'; $f.ClientSize=New-Object Drawing.Size(1000,660); $f.StartPosition='CenterScreen'
$f.BackColor=$bg; $f.ForeColor=$tx; $f.Font=$fUI; $f.FormBorderStyle='Sizable'; $f.MaximizeBox=$true; $f.MinimumSize=$f.Size
try{ $f.Icon=[Drawing.Icon]::FromHandle((New-FXBitmap 64).GetHicon()) }catch{}
DoubleBuffer $f

function Pnl($parent,$x,$y,$w,$h,$col,$r=0){
  $p=New-Object Windows.Forms.Panel; $p.Location=New-Object Drawing.Point($x,$y); $p.Size=New-Object Drawing.Size($w,$h)
  $p.BackColor=$col; DoubleBuffer $p; if($r){ Round $p $r }; $parent.Controls.Add($p); $p }

function Lbl($t,$x,$y,$sz,$col,$bold,$parent=$f){
  $l=New-Object Windows.Forms.Label; $l.Text=$t; $l.AutoSize=$true; $l.Location=New-Object Drawing.Point($x,$y)
  $fam=if($bold){'Segoe UI Semibold'}else{'Segoe UI'}; $l.Font=New-Object Drawing.Font($fam,[single]$sz)
  $l.ForeColor=$col; $parent.Controls.Add($l); $l }

# style: primary | secondary | card
function Btn($t,$x,$y,$w,$h,$act,$style='secondary',$parent=$f){
  $b=New-Object Windows.Forms.Button; $b.Text=$t; $b.Location=New-Object Drawing.Point($x,$y); $b.Size=New-Object Drawing.Size($w,$h)
  $b.FlatStyle='Flat'; $b.FlatAppearance.BorderSize=0; $b.Cursor='Hand'; $b.Font=$fBtn; $b.UseVisualStyleBackColor=$false
  switch($style){
    'primary'  { $b.BackColor=$pr; $b.ForeColor=$white; $b.FlatAppearance.MouseOverBackColor=$prh; $b.FlatAppearance.MouseDownBackColor=$prd }
    'card'     { $b.BackColor=$hv; $b.ForeColor=$tx; $b.FlatAppearance.MouseOverBackColor=(C 58 51 88); $b.FlatAppearance.MouseDownBackColor=$bd }
    default    { $b.BackColor=$pn; $b.ForeColor=$tx; $b.FlatAppearance.MouseOverBackColor=$hv; $b.FlatAppearance.MouseDownBackColor=$bd }
  }
  if($act){ $b.Add_Click($act) }
  DoubleBuffer $b
  $b.Add_Paint({ try{
    $g=$_.Graphics; $g.SmoothingMode='AntiAlias'; $g.Clear($this.Parent.BackColor)
    $rp=RoundPath 0 0 $this.Width $this.Height (Px 9); $g.FillPath((Br (Get-Col $this)),$rp); $rp.Dispose()
    [Windows.Forms.TextRenderer]::DrawText($g,$this.Text,$this.Font,$this.ClientRectangle,$this.ForeColor,[Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,EndEllipsis,NoPrefix') }catch{} })
  $b.Add_MouseEnter({ Fade-To $this $this.FlatAppearance.MouseOverBackColor })
  $b.Add_MouseLeave({ Fade-To $this $this.BackColor })
  $b.Add_MouseDown({ $script:fadeTo.Remove($this); Set-Col $this $this.FlatAppearance.MouseDownBackColor })
  $b.Add_MouseUp({ Fade-To $this $this.FlatAppearance.MouseOverBackColor })
  $parent.Controls.Add($b); $b }

# ---- Smooth dark list with optional round checkboxes ----
function New-List($parent,$x,$y,$w,$h,$cols,$checks){
  $hp=Pnl $parent $x $y $w $h $pn 14; $hp.Tag='listhost'
  $L=New-Object Windows.Forms.ListView
  $L.Location=New-Object Drawing.Point(8,8); $L.Size=New-Object Drawing.Size(($w-16),($h-14)); $L.Anchor='Top,Bottom,Left,Right'
  $L.View='Details'; $L.FullRowSelect=$true; $L.BorderStyle='None'; $L.HeaderStyle='Nonclickable'
  $L.BackColor=$pn; $L.ForeColor=$tx; $L.Font=$fRow; $L.SmallImageList=$rowImgs; $L.OwnerDraw=$true
  $L.HideSelection=$true; $L.MultiSelect=$true
  $L.Tag=if($checks){'check'}else{'plain'}
  for($i=0;$i -lt $cols.Count;$i++){ $wd=if($i -eq $cols.Count-1){-2}else{Px $cols[$i][1]}; [void]$L.Columns.Add($cols[$i][0],$wd) }
  $L.Add_DrawColumnHeader({ try{
    $e=$_; $g=$e.Graphics; $r=$e.Bounds; $LV=$e.Header.ListView
    $g.FillRectangle((Br $sb),$r)
    $g.FillRectangle((Br $bd),$r.X,($r.Bottom-1),$r.Width,1)
    $o=if($e.ColumnIndex -eq 0 -and $LV.Tag -eq 'check'){Px 38}else{Px 12}
    $tr=New-Object Drawing.Rectangle(($r.X+$o),$r.Y,[math]::Max(0,$r.Width-$o-4),$r.Height)
    [Windows.Forms.TextRenderer]::DrawText($g,$e.Header.Text,$fHdr,$tr,$mu,[Windows.Forms.TextFormatFlags]'VerticalCenter,Left,EndEllipsis') }catch{} })
  $L.Add_DrawItem({ try{
    $e=$_; $LV=$e.Item.ListView; $g=$e.Graphics; $r=$e.Bounds
    $g.FillRectangle((Br $pn),$r)
    $hl=if($e.Item.Selected){$hv}elseif($script:hotRow[$LV] -eq $e.ItemIndex){$hot}else{$null}
    if($hl){ $g.SmoothingMode='AntiAlias'
      $rp=RoundPath ($r.X+2) ($r.Y+2) ($r.Width-4) ($r.Height-4) (Px 8); $g.FillPath((Br $hl),$rp); $rp.Dispose()
      $g.SmoothingMode='Default' } }catch{} })
  $L.Add_DrawSubItem({ try{
    $e=$_; $LV=$e.Item.ListView; $g=$e.Graphics; $r=$e.Bounds
    if($e.ColumnIndex -eq 0){ $r=New-Object Drawing.Rectangle($r.X,$r.Y,$LV.Columns[0].Width,$r.Height) }
    $x=$r.X+(Px 12)
    if($e.ColumnIndex -eq 0 -and $LV.Tag -eq 'check'){
      if($null -ne $e.Item.Tag.Data){
        $g.SmoothingMode='AntiAlias'; $bs=Px 18; $by=$r.Y+[int](($r.Height-$bs)/2); $bp=RoundPath $x $by $bs $bs (Px 6)
        if($e.Item.Tag.On){
          $g.FillPath((Br $pr),$bp); $pen=New-Object Drawing.Pen($white,[single](2*$S)); $pen.StartCap='Round'; $pen.EndCap='Round'; $pen.LineJoin='Round'
          $pts=[Drawing.PointF[]]@((New-Object Drawing.PointF(($x+5*$S),($by+9*$S))),(New-Object Drawing.PointF(($x+8*$S),($by+12*$S))),(New-Object Drawing.PointF(($x+13*$S),($by+6*$S))))
          $g.DrawLines($pen,$pts); $pen.Dispose() }
        else{ $pen=New-Object Drawing.Pen($bd,1.5); $g.DrawPath($pen,$bp); $pen.Dispose() }
        $g.SmoothingMode='Default'; $bp.Dispose() }
      $x+=Px 28 }
    $txt=$e.SubItem.Text
    if($e.ColumnIndex -gt 0 -and $txt -in 'Active','On','Off','Enabled','Disabled'){
      $isOn=($txt -in 'Active','On','Enabled')
      $label=if($txt -in 'Active','On'){ 'ON' }elseif($txt -eq 'Off'){ 'OFF' }else{ $txt.ToUpper() }
      $tw=[Windows.Forms.TextRenderer]::MeasureText($label,$fPill).Width
      $pw=[math]::Max((Px 46),$tw+(Px 18)); $ph=Px 20; $py=$r.Y+[int](($r.Height-$ph)/2)
      $g.SmoothingMode='AntiAlias'
      $pp=RoundPath $x $py $pw $ph ([int]($ph/2)); $g.FillPath((Br $(if($isOn){$pillOn}else{$pillOff})),$pp); $pp.Dispose()
      if($isOn){ $g.FillEllipse((Br $okc),($x+(Px 8)),($py+[int](($ph-(Px 6))/2)),(Px 6),(Px 6)) }
      $g.SmoothingMode='Default'
      $lr=New-Object Drawing.Rectangle($(if($isOn){ $x+(Px 8) }else{ $x }),$py,$(if($isOn){ $pw-(Px 8) }else{ $pw }),$ph)
      [Windows.Forms.TextRenderer]::DrawText($g,$label,$fPill,$lr,$(if($isOn){$okc}else{$mu}),[Windows.Forms.TextFormatFlags]'HorizontalCenter,VerticalCenter,NoPrefix')
      return }
    $fc=if($e.Item.UseItemStyleForSubItems){$e.Item.ForeColor}else{$e.SubItem.ForeColor}
    $tr=New-Object Drawing.Rectangle($x,$r.Y,[math]::Max(0,$r.Right-$x-6),$r.Height)
    [Windows.Forms.TextRenderer]::DrawText($g,$e.SubItem.Text,$LV.Font,$tr,$fc,[Windows.Forms.TextFormatFlags]'VerticalCenter,Left,EndEllipsis,NoPrefix') }catch{} })
  $L.Add_SizeChanged({ try{ $this.Columns[$this.Columns.Count-1].Width=-2 }catch{} })
  $L.Add_MouseMove({ try{
    $h=$this.HitTest($_.Location); $i=if($h.Item){$h.Item.Index}else{-1}
    if($script:hotRow[$this] -ne $i){ $script:hotRow[$this]=$i; $this.Invalidate() } }catch{} })
  $L.Add_MouseLeave({ $script:hotRow[$this]=-1; $this.Invalidate() })
  if($checks){
    $L.Add_MouseClick({ $h=$this.HitTest($_.Location)
      if($h.Item -and $null -ne $h.Item.Tag.Data){ $h.Item.Tag.On=-not $h.Item.Tag.On; $this.Invalidate($h.Item.Bounds) } })
    $L.Add_KeyDown({ if($_.KeyCode -eq 'Space'){
      foreach($it in $this.SelectedItems){ if($null -ne $it.Tag.Data){ $it.Tag.On=-not $it.Tag.On } }
      $this.Invalidate(); $_.Handled=$true } })
  }
  DoubleBuffer $L; $hp.Controls.Add($L); $script:themed+=$L; $L }

function New-Summary($parent){
  $l=Lbl '' 452 22 10 $tx $true $parent
  $bar=New-Object Windows.Forms.Panel; $bar.Location=New-Object Drawing.Point(452,50); $bar.Size=New-Object Drawing.Size(310,8)
  $bar.BackColor=$bg; $bar.Tag=0.0; DoubleBuffer $bar; $parent.Controls.Add($bar)
  $bar.Add_Paint({ try{
    $g=$_.Graphics; $g.SmoothingMode='AntiAlias'; $w=$this.Width; $h=$this.Height
    $p1=RoundPath 0 0 $w $h ([int]($h/2)); $g.FillPath((Br $pn),$p1); $p1.Dispose()
    $fw=[int]($w*[double]$this.Tag)
    if($fw -gt 0){ $p2=RoundPath 0 0 ([math]::Max($h,$fw)) $h ([int]($h/2)); $g.FillPath((Br $(if([double]$this.Tag -ge 1){$okc}else{$pr})),$p2); $p2.Dispose() } }catch{} })
  [pscustomobject]@{ Label=$l; Bar=$bar } }
function Set-Summary($sum,$on,$total,$what){
  $sum.Label.Text=if($total -gt 0 -and $on -eq $total){ "All $total $what on" }else{ "$on of $total $what on" }
  $sum.Label.ForeColor=if($total -gt 0 -and $on -eq $total){ $okc }else{ $tx }
  $sum.Label.Left=$sum.Bar.Right-$sum.Label.Width
  $sum.Bar.Tag=if($total -gt 0){ [double]$on/$total }else{ 0.0 }; $sum.Bar.Invalidate() }

function Add-Row($L,$cells,$data,$col=$tx,$on=$false){
  $it=New-Object Windows.Forms.ListViewItem([string]$cells[0])
  for($i=1;$i -lt $cells.Count;$i++){ [void]$it.SubItems.Add([string]$cells[$i]) }
  $it.ForeColor=$col; $it.Tag=[pscustomobject]@{On=[bool]$on;Data=$data}; [void]$L.Items.Add($it); $it }
function Set-CellColor($it,$i,$col){ $it.UseItemStyleForSubItems=$false; $it.SubItems[$i].ForeColor=$col }
function Get-Picked($L){
  $x=@($L.Items | Where-Object { $_.Tag.On -and $null -ne $_.Tag.Data })
  if($x.Count -eq 0){ $x=@($L.SelectedItems | Where-Object { $null -ne $_.Tag.Data }) }
  $x }
function Fmt-Size($b){
  if($b -ge 1GB){'{0:N1} GB' -f ($b/1GB)}elseif($b -ge 1MB){'{0:N0} MB' -f ($b/1MB)}elseif($b -gt 0){'{0:N0} KB' -f ($b/1KB)}else{'0 MB'} }

# =========================================================
#  Layout: sidebar, pages, status bar
# =========================================================
$side=Pnl $f 0 0 210 660 $sb
$navBar=Pnl $side 12 101 3 22 $ac
$logo=New-Object Windows.Forms.PictureBox; $logo.Location=New-Object Drawing.Point(20,22); $logo.Size=New-Object Drawing.Size(36,36)
$logo.Image=New-FXBitmap (Px 72); $logo.SizeMode='Zoom'; $side.Controls.Add($logo)
[void](Lbl 'FX Tweaks' 64 19 13 $tx $true $side)
$userLbl=Lbl 'Guest' 66 43 8.5 $ac $false $side
$verLbl=Lbl "v$FX_VERSION" 12 636 8 $mu $false $side

$stBar=Pnl $f 210 626 790 34 $bg
[void](Pnl $stBar 0 0 790 1 $bd)
$st=Lbl 'Ready' 28 8 9 $mu $false $stBar

$pages=[ordered]@{}; $script:navs=@(); $script:navY=92; $script:cur=''
function New-Page($key,$title,$sub){
  $p=Pnl $f 210 0 790 626 $bg; $p.Visible=$false
  [void](Lbl $title 26 18 18 $tx $true $p)
  [void](Lbl $sub 29 56 9.5 $mu $false $p)
  $pages[$key]=$p; $p }

function NavItem($key,$glyph,$text){
  $p=Pnl $side 12 $script:navY 186 40 $sb 8; $p.Tag=$key; $p.Cursor='Hand'
  $i=New-Object Windows.Forms.Label; $i.Text=[string][char]$glyph; $i.Font=$fIcon; $i.AutoSize=$true
  $i.Location=New-Object Drawing.Point(14,11); $i.ForeColor=$mu; $p.Controls.Add($i)
  $t=Lbl $text 42 9 10 $mu $false $p
  foreach($c in @($p,$i,$t)){
    $c.Tag=$key; $c.Cursor='Hand'
    $c.Add_Click({ Show-Page $this.Tag })
    $c.Add_MouseEnter({ $n=if($this -is [Windows.Forms.Label]){$this.Parent}else{$this}; if($n.Tag -ne $script:cur){ Fade-To $n $hot } })
    $c.Add_MouseLeave({ $n=if($this -is [Windows.Forms.Label]){$this.Parent}else{$this}; if($n.Tag -ne $script:cur){ Fade-To $n $sb } }) }
  $script:navY+=46; $script:navs+=$p }

# sliding accent bar in the sidebar
$script:barTarget=101
$navTimer=New-Object Windows.Forms.Timer; $navTimer.Interval=12
$navTimer.Add_Tick({
  $d=$script:barTarget-$navBar.Top
  if([math]::Abs($d) -le 1){ $navBar.Top=$script:barTarget; $navTimer.Stop() }
  else{ $navBar.Top+=[int][math]::Round($d*0.3) } })

$loaders=@{}; $loaded=@{}
function Show-Page($key){
  if($key -eq $script:cur){ return }
  $script:cur=$key; $f.SuspendLayout()
  foreach($k in $pages.Keys){ $pages[$k].Visible=($k -eq $key) }
  $pages[$key].Size=New-Object Drawing.Size(($f.ClientSize.Width-$side.Width),($f.ClientSize.Height-$stBar.Height))
  foreach($n in $script:navs){
    $act=($n.Tag -eq $key); $script:fadeTo.Remove($n); $n.BackColor=if($act){$pn}else{$sb}
    $n.Controls[0].ForeColor=if($act){$ac}else{$mu}; $n.Controls[1].ForeColor=if($act){$tx}else{$mu}
    if($act){ $script:barTarget=$n.Top+[int](($n.Height-$navBar.Height)/2) } }
  $f.ResumeLayout(); $navTimer.Start(); DE
  if($loaders.Contains($key) -and (-not $loaded[$key] -or $key -in 'apps','fn','acct','prof')){ $loaded[$key]=$true; & $loaders[$key] } }

function Busy($m){ $f.Cursor='WaitCursor'; $st.ForeColor=$mu; $st.Text=$m; DE }
function Done{ $f.Cursor='Default'; $st.Text='Ready'; $st.ForeColor=$mu }

# =========================================================
#  Registry helpers + tweaks
# =========================================================
function RegSet($k,$n,$v,$t='REG_DWORD'){ reg add $k /v $n /t $t /d $v /f | Out-Null }
function RegDel($k,$n){ reg delete $k /v $n /f 2>$null | Out-Null }
function RegGet($path,$name){ (Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue).$name }
$SP='HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
$GM='HKCU\System\GameConfigStore'
$CDM='HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$TCPIF='HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
$GUID='([0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12})'

function T($name,$desc,$rec,$test,$on,$off){ [pscustomobject]@{Name=$name;Desc=$desc;Rec=$rec;Test=$test;On=$on;Off=$off} }
function Test-Tweak($t){ try{ [bool](& $t.Test) }catch{ $false } }

$FN='FortniteClient-Win64-Shipping'
$IFEO="HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$FN.exe\PerfOptions"
$GPUP='HKCU\Software\Microsoft\DirectX\UserGpuPreferences'
$LAYR='HKCU\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
function Find-Fortnite{
  $dirs=@()
  try{ (Get-Content "$env:ProgramData\Epic\UnrealEngineLauncher\LauncherInstalled.dat" -Raw | ConvertFrom-Json).InstallationList |
    Where-Object { $_.AppName -eq 'Fortnite' } | ForEach-Object { $dirs+=$_.InstallLocation } }catch{}
  foreach($m in Get-ChildItem "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests\*.item" -ErrorAction SilentlyContinue){
    try{ $j=Get-Content $m.FullName -Raw | ConvertFrom-Json; if($j.AppName -eq 'Fortnite' -or $j.DisplayName -eq 'Fortnite'){ $dirs+=$j.InstallLocation } }catch{} }
  $dirs+="$env:ProgramFiles\Epic Games\Fortnite"
  foreach($d in $dirs){ if($d){ $exe=Join-Path $d "FortniteGame\Binaries\Win64\$FN.exe"; if(Test-Path $exe){ return $exe } } }
  $null }
$script:fnExe=Find-Fortnite

if((RegGet 'HKCU:\Software\FXTweaks' VibranceTrying) -eq 1){ RegSet 'HKCU\Software\FXTweaks' Vibrance 50; RegSet 'HKCU\Software\FXTweaks' VibranceTrying 0; $script:vivCrashed=$true }
Step 'Loading tweaks...'
$tweaks=@()
$tweaks+=T 'Fortnite: high priority + max GPU' 'Fortnite always starts with top priority' $true {
  (RegGet "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\$FN.exe\PerfOptions" CpuPriorityClass) -eq 3
} {
  RegSet $IFEO CpuPriorityClass 3
  if($script:fnExe){ RegSet $GPUP $script:fnExe 'GpuPreference=2;' REG_SZ; RegSet $LAYR $script:fnExe '~ DISABLEDXMAXIMIZEDWINDOWEDMODE' REG_SZ }
} {
  RegDel $IFEO CpuPriorityClass
  if($script:fnExe){ RegDel $GPUP $script:fnExe; RegDel $LAYR $script:fnExe }
}
$tweaks+=T 'Ultimate Performance power plan' 'Keeps your CPU at full speed' $true {
  $o=powercfg /getactivescheme | Out-String; $s=RegGet 'HKCU:\Software\FXTweaks' UltimatePlan
  ($o -match '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c') -or ($o -match 'e9a42b02-d5df-448d-aa00-03f14749eb61') -or ($s -and $o -match [regex]::Escape($s))
} {
  $s=RegGet 'HKCU:\Software\FXTweaks' UltimatePlan; $l=powercfg /list | Out-String
  if($s -and $l -match [regex]::Escape($s)){ powercfg /setactive $s | Out-Null; return }
  if($l -match "$GUID\s+\(Ultimate Performance\)"){ powercfg /setactive $Matches[1] | Out-Null; RegSet 'HKCU\Software\FXTweaks' UltimatePlan $Matches[1] REG_SZ; return }
  $o=powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 2>&1 | Out-String
  if($o -match $GUID){ $g=$Matches[1]; powercfg /setactive $g | Out-Null; RegSet 'HKCU\Software\FXTweaks' UltimatePlan $g REG_SZ }
  else{ powercfg /setactive SCHEME_MIN | Out-Null }
} { powercfg /setactive SCHEME_BALANCED | Out-Null }

$tweaks+=T 'Game Mode, no background capture' 'Game Mode on, Game Bar recording off' $true {
  (RegGet 'HKCU:\System\GameConfigStore' GameDVR_Enabled) -eq 0
} {
  RegSet $GM GameDVR_Enabled 0; RegSet 'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR' AppCaptureEnabled 0
  RegSet 'HKCU\Software\Microsoft\GameBar' AutoGameModeEnabled 1; RegSet 'HKCU\Software\Microsoft\GameBar' AllowAutoGameMode 1
} { RegSet $GM GameDVR_Enabled 1 }

$tweaks+=T 'Fullscreen optimizations off' 'Lower input lag in fullscreen games' $true {
  (RegGet 'HKCU:\System\GameConfigStore' GameDVR_FSEBehaviorMode) -eq 2
} {
  RegSet $GM GameDVR_FSEBehaviorMode 2; RegSet $GM GameDVR_HonorUserFSEBehaviorMode 1; RegSet $GM GameDVR_DXGIHonorFSEWindowsCompatible 1
} {
  RegSet $GM GameDVR_FSEBehaviorMode 0; RegSet $GM GameDVR_HonorUserFSEBehaviorMode 0; RegSet $GM GameDVR_DXGIHonorFSEWindowsCompatible 0
}

$tweaks+=T 'Game CPU/GPU priority' 'Games go first, network throttling off' $true {
  (RegGet 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' SystemResponsiveness) -eq 0
} {
  RegSet "$SP" SystemResponsiveness 0; RegSet "$SP" NetworkThrottlingIndex 0xffffffff
  RegSet "$SP\Tasks\Games" 'GPU Priority' 8; RegSet "$SP\Tasks\Games" Priority 6
  RegSet "$SP\Tasks\Games" 'Scheduling Category' High REG_SZ; RegSet "$SP\Tasks\Games" 'SFIO Priority' High REG_SZ
} {
  RegSet "$SP" SystemResponsiveness 20; RegSet "$SP" NetworkThrottlingIndex 10
  RegSet "$SP\Tasks\Games" 'GPU Priority' 8; RegSet "$SP\Tasks\Games" Priority 2
  RegSet "$SP\Tasks\Games" 'Scheduling Category' Medium REG_SZ; RegSet "$SP\Tasks\Games" 'SFIO Priority' Normal REG_SZ
}

$tweaks+=T "Nagle's algorithm off" 'Sends game packets right away' $true {
  @(Get-ChildItem $TCPIF -ErrorAction SilentlyContinue | Where-Object { (Get-ItemProperty $_.PSPath).TCPNoDelay -eq 1 }).Count -gt 0
} {
  foreach($k in Get-ChildItem $TCPIF -ErrorAction SilentlyContinue){
    $p=Get-ItemProperty $k.PSPath
    if($p.DhcpIPAddress -or $p.IPAddress){
      Set-ItemProperty $k.PSPath TcpAckFrequency 1 -Type DWord; Set-ItemProperty $k.PSPath TCPNoDelay 1 -Type DWord } }
} {
  foreach($k in Get-ChildItem $TCPIF -ErrorAction SilentlyContinue){
    Remove-ItemProperty $k.PSPath -Name TcpAckFrequency,TCPNoDelay -ErrorAction SilentlyContinue }
}

$tweaks+=T 'Update sharing off' 'Stops uploading updates to other PCs' $true {
  (RegGet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' DODownloadMode) -eq 0
} { RegSet 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' DODownloadMode 0
} { RegDel 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' DODownloadMode }

$tweaks+=T 'Power throttling off' 'Windows stops slowing apps to save power' $true {
  (RegGet 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' PowerThrottlingOff) -eq 1
} { RegSet 'HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' PowerThrottlingOff 1
} { RegDel 'HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' PowerThrottlingOff }

$tweaks+=T 'Mouse acceleration off' 'Consistent aim (applies after sign-out)' $true {
  (RegGet 'HKCU:\Control Panel\Mouse' MouseSpeed) -eq '0'
} {
  RegSet 'HKCU\Control Panel\Mouse' MouseSpeed 0 REG_SZ; RegSet 'HKCU\Control Panel\Mouse' MouseThreshold1 0 REG_SZ; RegSet 'HKCU\Control Panel\Mouse' MouseThreshold2 0 REG_SZ
} {
  RegSet 'HKCU\Control Panel\Mouse' MouseSpeed 1 REG_SZ; RegSet 'HKCU\Control Panel\Mouse' MouseThreshold1 6 REG_SZ; RegSet 'HKCU\Control Panel\Mouse' MouseThreshold2 10 REG_SZ
}

$tweaks+=T 'Sticky Keys popup off' 'No popup when you spam Shift in game' $true {
  (RegGet 'HKCU:\Control Panel\Accessibility\StickyKeys' Flags) -eq '506'
} { RegSet 'HKCU\Control Panel\Accessibility\StickyKeys' Flags 506 REG_SZ
} { RegSet 'HKCU\Control Panel\Accessibility\StickyKeys' Flags 510 REG_SZ }

$tweaks+=T 'Startup delay removed' 'Startup apps launch without waiting' $true {
  (RegGet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' StartupDelayInMSec) -eq 0
} { RegSet 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' StartupDelayInMSec 0
} { RegDel 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' StartupDelayInMSec }

$tweaks+=T 'Tips and suggestions off' 'Fewer pop-ups and ads in Windows' $true {
  ((RegGet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' SystemPaneSuggestionsEnabled) -eq 0) -and
  ((RegGet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' SoftLandingEnabled) -eq 0)
} {
  foreach($n in 'SystemPaneSuggestionsEnabled','SoftLandingEnabled','SubscribedContent-338389Enabled','SubscribedContent-310093Enabled'){ RegSet $CDM $n 0 }
} {
  foreach($n in 'SystemPaneSuggestionsEnabled','SoftLandingEnabled','SubscribedContent-338389Enabled','SubscribedContent-310093Enabled'){ RegSet $CDM $n 1 }
}

$tweaks+=T 'Transparency effects off' 'Frees up a little GPU power' $true {
  (RegGet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' EnableTransparency) -eq 0
} { RegSet 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' EnableTransparency 0
} { RegSet 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' EnableTransparency 1 }

$tweaks+=T 'Fewer animations' 'Snappier windows and taskbar' $false {
  (RegGet 'HKCU:\Control Panel\Desktop\WindowMetrics' MinAnimate) -eq '0'
} {
  RegSet 'HKCU\Control Panel\Desktop\WindowMetrics' MinAnimate 0 REG_SZ; RegSet 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' TaskbarAnimations 0
} {
  RegSet 'HKCU\Control Panel\Desktop\WindowMetrics' MinAnimate 1 REG_SZ; RegSet 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' TaskbarAnimations 1
}

$tweaks+=T 'Background Store apps off' 'May delay notifications from Store apps' $false {
  (RegGet 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' GlobalUserDisabled) -eq 1
} { RegSet 'HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' GlobalUserDisabled 1
} { RegSet 'HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' GlobalUserDisabled 0 }

$tweaks+=T 'Hardware GPU scheduling' 'Newer GPUs only, needs a restart' $false {
  (RegGet 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' HwSchMode) -eq 2
} { RegSet 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' HwSchMode 2
} { RegSet 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' HwSchMode 1 }

$tweaks+=T 'Cloudflare DNS (1.1.1.1)' 'Faster lookups; skip on work networks' $false {
  @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses -contains '1.1.1.1' }).Count -gt 0
} {
  Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
    Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses '1.1.1.1','1.0.0.1' }
  ipconfig /flushdns | Out-Null
} {
  Get-NetAdapter -ErrorAction SilentlyContinue | ForEach-Object { Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ResetServerAddresses -ErrorAction SilentlyContinue }
}

$tweaks+=T 'NVIDIA potato textures' 'Flat, smooth textures in Fortnite (NVIDIA only)' $false {
  (RegGet 'HKCU:\Software\FXTweaks' NvPotato) -eq 1
} { if(-not (Set-NvPotato $true)){ throw 'NVIDIA potato could not be turned on' }
} { if(-not (Set-NvPotato $false)){ throw 'NVIDIA potato could not be turned off' } }

$tweaks+=T 'Network power saving off' 'Stops ping spikes from adapter sleep' $true {
  @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } |
    Get-NetAdapterPowerManagement -ErrorAction SilentlyContinue | Where-Object { "$($_.AllowComputerToTurnOffDevice)" -eq 'Disabled' }).Count -gt 0
} {
  Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {
    Disable-NetAdapterPowerManagement -Name $_.Name -NoRestart -Confirm:$false -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name $_.Name -RegistryKeyword '*EEE' -RegistryValue 0 -NoRestart -Confirm:$false -ErrorAction SilentlyContinue }
} {
  Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object {
    Enable-NetAdapterPowerManagement -Name $_.Name -NoRestart -Confirm:$false -ErrorAction SilentlyContinue
    Set-NetAdapterAdvancedProperty -Name $_.Name -RegistryKeyword '*EEE' -RegistryValue 1 -NoRestart -Confirm:$false -ErrorAction SilentlyContinue }
}

$tweaks+=T 'Prioritize Fortnite traffic' 'Marks Fortnite packets high priority (QoS)' $true {
  [bool](Get-NetQosPolicy -Name 'FX Fortnite' -ErrorAction SilentlyContinue)
} {
  RegSet 'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\QoS' 'Do not use NLA' 1 REG_SZ
  if(-not (Get-NetQosPolicy -Name 'FX Fortnite' -ErrorAction SilentlyContinue)){
    New-NetQosPolicy -Name 'FX Fortnite' -AppPathNameMatchCondition "$FN.exe" -DSCPAction 46 -NetworkProfile All -ErrorAction Stop | Out-Null }
} { Remove-NetQosPolicy -Name 'FX Fortnite' -Confirm:$false -ErrorAction SilentlyContinue }

$tweaks+=T 'Pause updates while gaming' 'Stops update downloads while Fortnite runs' $true {
  (RegGet 'HKCU:\Software\FXTweaks' PauseUpdates) -eq 1
} { RegSet 'HKCU\Software\FXTweaks' PauseUpdates 1 } { RegSet 'HKCU\Software\FXTweaks' PauseUpdates 0 }

$tweaks+=T 'Game Bar overlay off' 'Removes the Win+G overlay hook from games' $true {
  (RegGet 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' AllowGameDVR) -eq 0
} { RegSet 'HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR' AllowGameDVR 0
} { RegDel 'HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR' AllowGameDVR }

$tweaks+=T 'Close browsers while gaming' 'Closes Chrome/Edge/Firefox when Fortnite starts' $false {
  (RegGet 'HKCU:\Software\FXTweaks' CloseBrowsers) -eq 1
} { RegSet 'HKCU\Software\FXTweaks' CloseBrowsers 1 } { RegSet 'HKCU\Software\FXTweaks' CloseBrowsers 0 }

$tweaks+=T 'Multiplane overlay off' 'Fixes flicker/stutter on some AMD PCs' $false {
  (RegGet 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' OverlayTestMode) -eq 5
} { RegSet 'HKLM\SOFTWARE\Microsoft\Windows\Dwm' OverlayTestMode 5
} { RegDel 'HKLM\SOFTWARE\Microsoft\Windows\Dwm' OverlayTestMode }

# =========================================================
#  HOME
# =========================================================
Step 'Building Home...'
$pgStart0=New-Page 'start0' 'Welcome' 'Your gaming optimizer. Pick something below, or use the menu on the left.'
function BigTile($x,$y,$glyph,$title,$desc,$act){
  $c=Pnl $pgStart0 $x $y 352 112 $pn 16; $c.Cursor='Hand'
  $ic=New-Object Windows.Forms.Label; $ic.Text=[string][char]$glyph; $ic.Font=New-Object Drawing.Font('Segoe MDL2 Assets',22); $ic.AutoSize=$true
  $ic.Location=New-Object Drawing.Point(20,20); $ic.ForeColor=$ac; $c.Controls.Add($ic)
  $tl=Lbl $title 70 20 13 $tx $true $c
  $ds=Lbl $desc 70 50 9 $mu $false $c; $ds.MaximumSize=New-Object Drawing.Size(260,0)
  foreach($z in @($c,$ic,$tl,$ds)){ $z.Cursor='Hand'; $z.Add_Click($act)
    $z.Add_MouseEnter({ $p=if($this -is [Windows.Forms.Label]){$this.Parent}else{$this}; Fade-To $p $hv })
    $z.Add_MouseLeave({ $p=if($this -is [Windows.Forms.Label]){$this.Parent}else{$this}; Fade-To $p $pn }) }
  $c }
[void](BigTile 28 100 0xE945 'Boost now' 'Apply every recommended tweak in one click.' { Show-Page 'home'; Quick-Boost })
[void](BigTile 410 100 0xE7FC 'Potato mode' 'Set Fortnite to the flat pro look for max FPS.' { Show-Page 'fn'; Apply-Potato })
[void](BigTile 28 232 0xE968 'Run ping test' 'Check your connection to the game servers.' { Show-Page 'home'; DE; Run-PingTest })
[void](BigTile 410 232 0xE74D 'Clean up files' 'Free disk space by removing junk files.' { Show-Page 'clean' })
$startHint=Lbl '' 28 372 9.5 $mu $false $pgStart0
[void](Btn 'Run the quick setup guide' 28 400 250 40 { Start-Wizard } 'primary' $pgStart0)

$pgHome=New-Page 'home' 'Home' 'Check your connection and boost your PC before you play.'

$card=Pnl $pgHome 28 92 734 92 $pn 16
[void](Lbl 'Quick Boost' 20 15 13 $tx $true $card)
$boost=Lbl '' 150 19 8.5 $tx $true $card
$boost.Padding=New-Object Windows.Forms.Padding(8,2,8,2)
[void](Lbl 'Applies every recommended tweak at once.' 21 52 9.5 $mu $false $card)
[void](Btn 'Undo all' 294 26 130 40 { Undo-All } 'card' $card)
[void](Btn 'Fix network' 434 26 130 40 {
  Busy 'Resetting your connection...'
  ipconfig /flushdns | Out-Null; ipconfig /release | Out-Null; ipconfig /renew | Out-Null
  Done; Log 'DNS flushed and connection renewed.' $ac } 'card' $card)
[void](Btn 'Boost now' 574 26 140 40 { Quick-Boost } 'primary' $card)

[void](Lbl 'Connection' 27 202 11 $tx $true $pgHome)
[void](Btn 'Lag spike test' 612 196 150 30 { Test-Bufferbloat } 'secondary' $pgHome)
function Run-PingTest{
  $t=[ordered]@{}
  $g=(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1).NextHop
  if($g -and $g -ne '0.0.0.0'){$t['Your Router']=$g}
  $t['Cloudflare']='1.1.1.1'; $t['Google DNS']='8.8.8.8'; $t['Quad9']='9.9.9.9'
  RunPing $t
  $r=$lvPing.Items | Where-Object {$_.Text -eq 'Your Router'}
  if($r -and ([int](($r.SubItems[1].Text) -replace '\D','0')) -gt 15){ Log 'Your router ping is high: use Ethernet or move closer to the router.' $warn } }
$pingBtn=Btn 'Run ping test' 28 232 150 36 { Run-PingTest } 'primary' $pgHome

[void](Btn 'Test Fortnite servers' 188 232 190 36 { Test-Fortnite } 'secondary' $pgHome)
$tbHost=Pnl $pgHome 388 232 234 36 $pn 10
$tb=New-Object Windows.Forms.TextBox; $tb.BorderStyle='None'; $tb.Location=New-Object Drawing.Point(12,9); $tb.Width=212
$tb.BackColor=$pn; $tb.ForeColor=$tx; $tb.Font=$fUI; $tbHost.Controls.Add($tb)
$tbHost.Add_Click({ $tb.Focus() })
[void](Btn 'Test server' 632 232 130 36 {
  $h=$tb.Text.Trim(); if(-not $h){ Log 'Type a server IP or address first.' $warn; return }
  RunPing ([ordered]@{ $h=$h }) } 'secondary' $pgHome)

$lvPing=New-List $pgHome 28 280 734 176 @(@('Target',170),@('Avg',80),@('Min',70),@('Max',70),@('Jitter',80),@('Loss',70),@('Rating',0)) $false

[void](Lbl 'Activity' 27 470 11 $tx $true $pgHome)
$logHost=Pnl $pgHome 28 498 734 112 $pn 14
$log=New-Object Windows.Forms.RichTextBox; $log.Location=New-Object Drawing.Point(14,10); $log.Size=New-Object Drawing.Size(712,94)
$log.ReadOnly=$true; $log.BackColor=$pn; $log.ForeColor=$tx; $log.BorderStyle='None'; $mono=if([Drawing.FontFamily]::Families.Name -contains 'Cascadia Mono'){'Cascadia Mono'}else{'Consolas'}; $log.Font=New-Object Drawing.Font($mono,9)
$logHost.Controls.Add($log); $script:themed+=$log
function Log($m,$col=$mu){
  $log.SelectionStart=$log.TextLength; $log.SelectionLength=0; $log.SelectionColor=$col
  $log.AppendText("[$(Get-Date -f HH:mm:ss)]  $m`n"); $log.ScrollToCaret()
  $st.Text=$m; $st.ForeColor=$col }

function Stats($t,$n){
  if($t.Count -eq 0){ return $null }
  $j=0; for($i=1;$i -lt $t.Count;$i++){ $j+=[math]::Abs($t[$i]-$t[$i-1]) }; if($t.Count -gt 1){ $j=$j/($t.Count-1) }
  $m=$t | Measure-Object -Average -Minimum -Maximum
  [pscustomobject]@{Avg=$m.Average;Min=$m.Minimum;Max=$m.Maximum;Jit=$j;Loss=[int](($n-$t.Count)*100/$n)} }
function PingHost($h){
  $p=New-Object Net.NetworkInformation.Ping; $t=@()
  for($i=0;$i -lt 10;$i++){
    try{ $r=$p.Send($h,1000); if($r.Status -eq 'Success'){ $t+=[int]$r.RoundtripTime } }catch{}
    DE; Start-Sleep -Milliseconds 80 }
  Stats $t 10 }
function TcpPing($h){
  try{ $ip=[Net.Dns]::GetHostAddresses($h) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -First 1 }catch{ return $null }
  if(-not $ip){ return $null }
  $t=@(); $sw=New-Object Diagnostics.Stopwatch
  for($i=0;$i -lt 6;$i++){
    $c=New-Object Net.Sockets.TcpClient
    try{ $sw.Restart(); $task=$c.ConnectAsync($ip,443)
      if($task.Wait(1500) -and $c.Connected){ $t+=[int]$sw.ElapsedMilliseconds } }catch{}
    $c.Close(); DE; Start-Sleep -Milliseconds 60 }
  Stats $t 6 }

function Rate($r){
  if($r.Loss -gt 2 -or $r.Avg -ge 100){return 'Poor'}
  if($r.Avg -lt 30 -and $r.Loss -eq 0 -and $r.Jit -lt 10){return 'Excellent'}
  if($r.Avg -lt 60){return 'Good'}; return 'Fair' }

function RunPing($targets,$mode='icmp'){
  if($script:busy){return}; $script:busy=$true; $lvPing.Items.Clear()
  $colors=@{Excellent=$okc;Good=(C 140 220 90);Fair=$warn;Poor=$bad}
  $best=$null; $bn=''
  foreach($k in $targets.Keys){
    Busy "Testing $k ..."
    $r=if($mode -eq 'tcp'){ TcpPing $targets[$k] }else{ PingHost $targets[$k] }
    if($r){ $rt=Rate $r
      [void](Add-Row $lvPing @($k,('{0:N0} ms' -f $r.Avg),"$($r.Min) ms","$($r.Max) ms",('{0:N1} ms' -f $r.Jit),"$($r.Loss)%",$rt) $k $colors[$rt])
      if(-not $best -or $r.Avg -lt $best.Avg){$best=$r;$bn=$k} }
    else{ [void](Add-Row $lvPing @($k,'-','-','-','-','100%','No response') $k $bad) }
    DE }
  Done; $script:busy=$false; $script:bestName=$bn
  if($best){ Log ("Best result: $bn at {0:N0} ms" -f $best.Avg) $ac
    if($script:user){ $ms=[int][math]::Round($best.Avg)
      if($script:user.stats.best -eq 0 -or $ms -lt $script:user.stats.best){ $script:user.stats.best=$ms }
      $script:user.stats.pings++; Add-History 'Ping test' ("$($bn): $ms ms") } }
  Log 'Tip: Ethernet beats Wi-Fi, and pausing downloads lowers jitter.' }

function Test-Bufferbloat{
  if($script:busy){ return }; $script:busy=$true
  Busy 'Lag spike test: measuring normal ping...'
  $base=PingHost '1.1.1.1'
  if(-not $base){ Done; $script:busy=$false; Log 'No internet connection to test.' $bad; return }
  Busy 'Lag spike test: measuring ping while downloading...'
  $wc=$null
  try{ [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $wc=New-Object Net.WebClient; [void]$wc.DownloadDataTaskAsync('https://speed.cloudflare.com/__down?bytes=100000000') }catch{}
  Start-Sleep -Milliseconds 700
  $load=PingHost '1.1.1.1'
  try{ $wc.CancelAsync(); $wc.Dispose() }catch{}
  Done; $script:busy=$false
  if(-not $load){ Log 'Your ping stopped completely during the download: big lag spikes.' $bad; return }
  $d=[math]::Max(0,$load.Avg-$base.Avg)
  $grade=if($d -lt 5){'A'}elseif($d -lt 30){'B'}elseif($d -lt 60){'C'}else{'D'}
  Log ("Lag spike test: {0:N0} ms normally, {1:N0} ms while downloading (+{2:N0} ms). Grade {3}." -f $base.Avg,$load.Avg,$d,$grade) $(if($grade -in 'A','B'){$okc}else{$warn})
  Add-History 'Lag spike test' ("Grade $grade (+{0:N0} ms)" -f $d)
  if($grade -in 'C','D'){ Log 'Downloads slow your game traffic. Turn on QoS/SQM in your router, or pause downloads and streams while you play.' $warn }
  else{ Log 'Your connection handles downloads well.' $okc } }

function Refresh-State{
  $rec=@($tweaks | Where-Object { $_.Rec }); $on=@($rec | Where-Object { Test-Tweak $_ }).Count
  if($on -eq $rec.Count){ $boost.Text='ON'; $boost.BackColor=$pr; $boost.ForeColor=$white }
  elseif($on -gt 0){ $boost.Text="$on of $($rec.Count) on"; $boost.BackColor=$hv; $boost.ForeColor=$ac }
  else{ $boost.Text='OFF'; $boost.BackColor=$hv; $boost.ForeColor=$mu }
  Round $boost 10 }

$fnRegions=[ordered]@{
  'Europe - Frankfurt'='dynamodb.eu-central-1.amazonaws.com'; 'Europe - London'='dynamodb.eu-west-2.amazonaws.com'
  'NA East - Virginia'='dynamodb.us-east-1.amazonaws.com'; 'NA - Ohio'='dynamodb.us-east-2.amazonaws.com'
  'NA West - Oregon'='dynamodb.us-west-2.amazonaws.com'; 'Middle East - Bahrain'='dynamodb.me-south-1.amazonaws.com'
  'Brazil - Sao Paulo'='dynamodb.sa-east-1.amazonaws.com'; 'Asia - Tokyo'='dynamodb.ap-northeast-1.amazonaws.com'
  'Oceania - Sydney'='dynamodb.ap-southeast-2.amazonaws.com' }
function Test-Fortnite{
  Log 'Testing the cloud locations where Fortnite servers run...'
  $script:bestName=''; RunPing $fnRegions 'tcp'
  if($script:bestName){ Log "Your best Fortnite region is $(($script:bestName -split ' - ')[0]). In Fortnite settings, set Matchmaking Region to it (or Auto)." $ac } }

function Get-FnState{
  if(-not (Test-Path $FNINI)){ return $null }
  $L=Read-Ini
  [pscustomobject]@{ Potato=(Test-Potato $L); Perf=((Get-Ini $L $RHI 'PreferredFeatureLevel') -eq 'es31'); Res=(Get-Ini $L $SGQ 'sg.ResolutionQuality') } }
function Check-FnKept{
  $a=$script:fnStart; $b=Get-FnState
  if(-not $a -or -not $b){ return }
  if($a.Potato -and -not $b.Potato){ Log 'Fortnite changed your Potato settings back when it closed. On the Fortnite page, tick Potato graphics + Lock settings and apply.' $warn }
  elseif($a.Perf -and -not $b.Perf){ Log 'Fortnite switched Rendering Mode away from Performance. Set it once in Fortnite: Settings > Video > Rendering Mode.' $warn }
  elseif($a.Potato){ Log 'Fortnite kept your Potato settings.' $okc } }
function Set-FnStatus($text,$col){ $fnLbl.Text=$text; $fnLbl.ForeColor=$col }
function Optimize-Fortnite($p){
  try{ $p.PriorityClass='High' }catch{}
  if(-not $script:fnExe){ try{ if($p.Path){ $script:fnExe=$p.Path } }catch{} }
  try{ & $fnTweak.On }catch{}
  Get-Process EpicGamesLauncher,EpicWebHelper -ErrorAction SilentlyContinue | ForEach-Object { try{ $_.PriorityClass='BelowNormal' }catch{} }
  if((RegGet 'HKCU:\Software\FXTweaks' PauseUpdates) -eq 1){
    $script:paused=@()
    foreach($svName in 'wuauserv','BITS','DoSvc','UsoSvc'){
      $sv=Get-Service $svName -ErrorAction SilentlyContinue
      if($sv -and $sv.Status -eq 'Running'){ try{ Stop-Service $svName -Force -ErrorAction Stop; $script:paused+=$svName }catch{} } }
    if($script:paused.Count){ Log 'Paused Windows Update downloads while you play.' $ac } }
  if((RegGet 'HKCU:\Software\FXTweaks' CloseBrowsers) -eq 1){
    $br=Get-Process chrome,msedge,firefox,opera,brave -ErrorAction SilentlyContinue
    if($br){ $br | Stop-Process -Force -ErrorAction SilentlyContinue; Log 'Closed web browsers for more FPS.' $ac } }
  $vib=RegGet 'HKCU:\Software\FXTweaks' Vibrance; if($vib -and [int]$vib -gt 50){ [void](Set-Vivid ([int]$vib) -quiet) }
  Set-FnStatus 'Fortnite: running, optimized' $okc
  Log 'Fortnite detected: optimized and set to high priority.' $ac }

$script:paused=@()
function Resume-Updates{
  if($script:paused.Count){ foreach($svName in $script:paused){ Start-Service $svName -ErrorAction SilentlyContinue }
    $script:paused=@(); Log 'Windows Update resumed.' } }

function Quick-Boost{
  Save-Snapshot 'Before Quick Boost' $true
  Busy 'Boosting...'; $n=0
  foreach($t in $tweaks | Where-Object { $_.Rec }){
    $st.Text="Applying: $($t.Name)"; DE
    try{ & $t.On; $n++ }catch{ Log "Skipped: $($t.Name)" $warn } }
  Done; Refresh-Opt; Refresh-State
  Add-Stat 'boosts'; Add-History 'Quick Boost' "$n tweaks applied"
  Log "Boost complete: $n tweaks applied. Restart your game (a PC restart applies everything)." $ac }

function Undo-All{
  Save-Snapshot 'Before Undo all' $true
  Busy 'Reverting tweaks...'; $n=0
  foreach($t in $tweaks){ if(Test-Tweak $t){ try{ & $t.Off; $n++ }catch{} }; DE }
  Done; Refresh-Opt; Refresh-State; Log "Reverted $n tweaks. Windows defaults restored." $ac }

# =========================================================
#  OPTIMIZE
# =========================================================
Step 'Building Optimize...'
$pgOpt=New-Page 'opt' 'Optimize' 'Pick the tweaks you want. Everything here can be reverted.'
[void](Btn 'Apply selected' 28 92 150 36 { Apply-Picked $true } 'primary' $pgOpt)
[void](Btn 'Revert selected' 188 92 150 36 { Apply-Picked $false } 'secondary' $pgOpt)
[void](Btn 'Select recommended' 348 92 170 36 {
  foreach($it in $lvOpt.Items){ $it.Tag.On=[bool]$it.Tag.Data.Rec }; $lvOpt.Invalidate() } 'secondary' $pgOpt)
[void](Btn 'Create restore point' 592 92 170 36 {
  Busy 'Creating a restore point (this can take a minute)...'
  try{
    RegSet 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' SystemRestorePointCreationFrequency 0
    Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
    Checkpoint-Computer -Description 'FX Tweaks' -RestorePointType MODIFY_SETTINGS -Confirm:$false -ErrorAction Stop
    Done; Log 'Restore point created.' $ac }
  catch{ Done; Log "Couldn't create a restore point: $($_.Exception.Message)" $bad } } 'secondary' $pgOpt)
$optSum=New-Summary $pgOpt
$lvOpt=New-List $pgOpt 28 140 734 470 @(@('Tweak',240),@('What it does',300),@('Recommended',110),@('Status',0)) $true

function Load-Opt{
  Busy 'Checking your current settings...'; $lvOpt.BeginUpdate(); $lvOpt.Items.Clear()
  foreach($t in $tweaks){
    $it=Add-Row $lvOpt @($t.Name,$t.Desc,$(if($t.Rec){'Yes'}else{''}),'') $t
    Set-CellColor $it 1 $mu; Set-CellColor $it 2 $ac }
  $lvOpt.EndUpdate(); Refresh-Opt; Done }
function Refresh-Opt{
  foreach($it in $lvOpt.Items){
    $a=Test-Tweak $it.Tag.Data
    $it.SubItems[3].Text=if($a){'Active'}else{'Off'}; Set-CellColor $it 3 $(if($a){$okc}else{$mu}) }
  $n=@($lvOpt.Items | Where-Object { $_.SubItems[3].Text -eq 'Active' }).Count
  Set-Summary $optSum $n $lvOpt.Items.Count 'tweaks'
  $lvOpt.Invalidate() }
function Apply-Picked($on){
  $sel=@(Get-Picked $lvOpt); if(!$sel){ Log 'Tick the tweaks you want first.' $warn; return }
  Save-Snapshot $(if($on){ 'Before applying tweaks' }else{ 'Before reverting tweaks' }) $true
  Busy 'Applying...'
  foreach($it in $sel){ $t=$it.Tag.Data
    try{ if($on){ & $t.On }else{ & $t.Off }; Log ("{0}: {1}" -f $(if($on){'Applied'}else{'Reverted'}),$t.Name) $ac }
    catch{ Log "Couldn't change: $($t.Name)" $bad }
    $it.Tag.On=$false; DE }
  Done; Refresh-Opt; Refresh-State }
$loaders['opt']={ Load-Opt }

# =========================================================
#  RUNNING APPS
# =========================================================
Step 'Building Running apps...'
$pgApps=New-Page 'apps' 'Running apps' "See what's using memory and close what you don't need."
[void](Btn 'Close selected' 28 92 150 36 { Close-Apps } 'primary' $pgApps)
[void](Btn 'Set high priority' 188 92 160 36 {
  $sel=@(Get-Picked $lvApps); if(!$sel){ Log 'Tick your game in the list first.' $warn; return }
  foreach($it in $sel){ Get-Process -Name $it.Tag.Data -ErrorAction SilentlyContinue | ForEach-Object { try{ $_.PriorityClass='High' }catch{} }
    Log "Set $($it.Text) to high priority." $ac } } 'secondary' $pgApps)
[void](Btn 'Refresh' 358 92 110 36 { Load-Apps } 'secondary' $pgApps)
$memLbl=Lbl '' 520 101 9.5 $mu $false $pgApps
$lvApps=New-List $pgApps 28 140 734 470 @(@('App',180),@('Description',250),@('Type',100),@('Processes',90),@('Memory',0)) $true

$protect='System','Idle','Registry','smss','csrss','wininit','winlogon','services','lsass','LsaIso','svchost','dwm','explorer',
  'fontdrvhost','sihost','ctfmon','RuntimeBroker','SearchHost','SearchIndexer','StartMenuExperienceHost','ShellExperienceHost',
  'TextInputHost','conhost','dllhost','taskhostw','audiodg','spoolsv','MsMpEng','NisSrv','SecurityHealthService',
  'SecurityHealthSystray','WmiPrvSE','LockApp','ApplicationFrameHost','Memory Compression','smartscreen','SgrmBroker',
  'WUDFHost','MpDefenderCoreService','SystemSettings','Widgets','WidgetService','UserOOBEBroker','CompPkgSrv'
function Load-Apps{
  Busy 'Loading running apps...'; $lvApps.BeginUpdate(); $lvApps.Items.Clear()
  $sid=(Get-Process -Id $PID).SessionId
  $procs=Get-Process | Where-Object { $_.SessionId -eq $sid -and $_.Id -ne $PID -and $protect -notcontains $_.ProcessName }
  $rows=foreach($g in ($procs | Group-Object ProcessName)){
    $desc=''; foreach($p in $g.Group){ try{ if($p.Description){ $desc=$p.Description; break } }catch{} }
    [pscustomobject]@{ Name=$g.Name; Desc=$desc; Win=(@($g.Group | Where-Object { $_.MainWindowTitle }).Count -gt 0)
      Count=$g.Count; Mem=($g.Group | Measure-Object WorkingSet64 -Sum).Sum } }
  foreach($r in ($rows | Sort-Object @{Expression={$_.Win};Descending=$true},@{Expression={$_.Mem};Descending=$true})){
    $it=Add-Row $lvApps @($r.Name,$r.Desc,$(if($r.Win){'App'}else{'Background'}),$r.Count,(Fmt-Size $r.Mem)) $r.Name
    Set-CellColor $it 1 $mu; Set-CellColor $it 2 $(if($r.Win){$ac}else{$mu}) }
  $lvApps.EndUpdate()
  try{ $os=Get-CimInstance Win32_OperatingSystem
    $memLbl.Text=('Memory in use: {0:N1} of {1:N1} GB' -f (($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)/1MB),($os.TotalVisibleMemorySize/1MB))
    $memLbl.Left=$pgApps.ClientSize.Width-(Px 28)-$memLbl.Width }catch{}
  Done }
function Close-Apps{
  $sel=@(Get-Picked $lvApps); if(!$sel){ Log 'Tick the apps you want to close first.' $warn; return }
  $names=($sel | ForEach-Object { $_.Text }) -join ', '
  $a=[Windows.Forms.MessageBox]::Show("Close $($names)?`n`nUnsaved work in these apps will be lost.",'Close apps','YesNo','Warning')
  if($a -ne 'Yes'){ return }
  foreach($it in $sel){ Get-Process -Name $it.Tag.Data -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
  Log "Closed $names." $ac; Start-Sleep -Milliseconds 300; Load-Apps }
$loaders['apps']={ Load-Apps }

# =========================================================
#  STARTUP APPS
# =========================================================
$pgStart=New-Page 'start' 'Startup apps' 'Fewer apps at startup means a faster boot and more free memory.'
[void](Btn 'Disable selected' 28 92 160 36 { Set-Startup $false } 'primary' $pgStart)
[void](Btn 'Enable selected' 198 92 150 36 { Set-Startup $true } 'secondary' $pgStart)
[void](Btn 'Refresh' 358 92 110 36 { Load-Startup } 'secondary' $pgStart)
$lvStart=New-List $pgStart 28 140 734 470 @(@('Name',200),@('Command',330),@('For',90),@('Status',0)) $true

$APR='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
$APM='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
$startupLocs=@(
  @{For='You';Run='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';Ap="$APR\Run"},
  @{For='All users';Run='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';Ap="$APM\Run"},
  @{For='All users';Run='HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run';Ap="$APM\Run32"})
function Add-StartRow($name,$cmd,$for,$ap){
  $b=(Get-ItemProperty $ap -Name $name -ErrorAction SilentlyContinue).$name
  $off=($b -and ($b[0] -band 1))
  $it=Add-Row $lvStart @($name,$cmd,$for,$(if($off){'Disabled'}else{'Enabled'})) ([pscustomobject]@{Name=$name;Ap=$ap})
  Set-CellColor $it 1 $mu; Set-CellColor $it 3 $(if($off){$mu}else{$okc}) }
function Load-Startup{
  Busy 'Reading startup apps...'; $lvStart.BeginUpdate(); $lvStart.Items.Clear()
  foreach($L in $startupLocs){
    $k=Get-Item $L.Run -ErrorAction SilentlyContinue; if(-not $k){ continue }
    foreach($n in $k.GetValueNames()){ if($n){ Add-StartRow $n ([string]$k.GetValue($n)) $L.For $L.Ap } } }
  foreach($file in Get-ChildItem ([Environment]::GetFolderPath('Startup')) -File -ErrorAction SilentlyContinue){
    if($file.Name -ne 'desktop.ini'){ Add-StartRow $file.Name $file.FullName 'You' "$APR\StartupFolder" } }
  $lvStart.EndUpdate(); Done }
function Set-Startup($enable){
  $sel=@(Get-Picked $lvStart); if(!$sel){ Log 'Tick the startup apps you want to change first.' $warn; return }
  foreach($it in $sel){ $d=$it.Tag.Data
    try{
      if(-not (Test-Path $d.Ap)){ New-Item $d.Ap -Force | Out-Null }
      $bytes=[byte[]](@($(if($enable){2}else{3})) + @(0)*11)
      New-ItemProperty -Path $d.Ap -Name $d.Name -Value $bytes -PropertyType Binary -Force | Out-Null
      Log ("{0} {1} at startup." -f $d.Name,$(if($enable){'will run'}else{'won''t run'})) $ac }
    catch{ Log "Couldn't change $($d.Name)." $bad } }
  Load-Startup }
$loaders['start']={ Load-Startup }

# =========================================================
#  CLEAN UP FILES
# =========================================================
Step 'Building Clean up...'
$pgClean=New-Page 'clean' 'Clean up files' "Free up disk space by removing files Windows doesn't need."
[void](Btn 'Clean selected' 28 92 150 36 { Clean-Junk } 'primary' $pgClean)
[void](Btn 'Scan again' 188 92 120 36 { Scan-Junk } 'secondary' $pgClean)
$junkTotal=Lbl '' 600 100 10 $ac $true $pgClean
$lvJunk=New-List $pgClean 28 140 734 470 @(@('Category',230),@('What it is',330),@('Size',0)) $true
$lvJunk.Add_MouseClick({ Update-JunkTotal })

function J($name,$desc,$paths,$rec,$filter='*',$svc=$null,$bin=$false){
  [pscustomobject]@{Name=$name;Desc=$desc;Paths=$paths;Rec=$rec;Filter=$filter;Svc=$svc;Bin=$bin;Size=0} }
$junk=@(
  (J 'Temporary files' 'Leftovers from apps and installers' @($env:TEMP,"$env:windir\Temp") $true),
  (J 'Windows Update cache' 'Update downloads that are already installed' @("$env:windir\SoftwareDistribution\Download") $true '*' 'wuauserv'),
  (J 'Update sharing cache' 'Update files kept to share with other PCs' @("$env:windir\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache") $true),
  (J 'Crash dumps and error reports' 'Logs from apps that crashed' @("$env:LOCALAPPDATA\CrashDumps","$env:ProgramData\Microsoft\Windows\WER\ReportArchive","$env:ProgramData\Microsoft\Windows\WER\ReportQueue") $true),
  (J 'Thumbnail cache' 'Picture previews, rebuilt when needed' @("$env:LOCALAPPDATA\Microsoft\Windows\Explorer") $false 'thumbcache_*.db'),
  (J 'Browser cache' 'Chrome, Edge and Firefox (close them first)' @("$env:LOCALAPPDATA\Google\Chrome\User Data\*\Cache","$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Cache","$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2") $false),
  (J 'Recycle Bin' 'Files you already deleted' @() $false '*' $null $true))

function Junk-Size($j){
  $s=0
  if($j.Bin){ try{ $sh=New-Object -ComObject Shell.Application; foreach($i in $sh.Namespace(10).Items()){ $s+=[double]$i.Size } }catch{}; return $s }
  foreach($p in $j.Paths){ foreach($rp in @(Resolve-Path $p -ErrorAction SilentlyContinue)){
    $m=Get-ChildItem -LiteralPath $rp.ProviderPath -Filter $j.Filter -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum
    if($m.Sum){ $s+=[double]$m.Sum }; DE } }
  $s }
function Update-JunkTotal{
  $s=0; foreach($it in $lvJunk.Items){ if($it.Tag.On){ $s+=$it.Tag.Data.Size } }
  $junkTotal.Text="Selected: $(Fmt-Size $s)"; $junkTotal.Left=$pgClean.ClientSize.Width-(Px 28)-$junkTotal.Width }
function Load-Junk{
  $lvJunk.Items.Clear()
  foreach($j in $junk){ $it=Add-Row $lvJunk @($j.Name,$j.Desc,'...') $j $tx $j.Rec; Set-CellColor $it 1 $mu }
  Scan-Junk }
function Scan-Junk{
  foreach($it in $lvJunk.Items){ $j=$it.Tag.Data; Busy "Scanning $($j.Name)..."
    $j.Size=Junk-Size $j; $it.SubItems[2].Text=Fmt-Size $j.Size; $lvJunk.Invalidate(); DE }
  Done; Update-JunkTotal }
function Clean-Junk{
  $sel=@(Get-Picked $lvJunk); if(!$sel){ Log 'Tick at least one category first.' $warn; return }
  $before=0; $after=0
  foreach($it in $sel){ $j=$it.Tag.Data; $before+=$j.Size; Busy "Cleaning $($j.Name)..."
    if($j.Svc){ Stop-Service $j.Svc -Force -ErrorAction SilentlyContinue }
    if($j.Bin){ Clear-RecycleBin -Force -Confirm:$false -ErrorAction SilentlyContinue }
    else{ foreach($p in $j.Paths){ foreach($rp in @(Resolve-Path $p -ErrorAction SilentlyContinue)){
      Get-ChildItem -LiteralPath $rp.ProviderPath -Filter $j.Filter -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; DE } } }
    if($j.Svc){ Start-Service $j.Svc -ErrorAction SilentlyContinue }
    $j.Size=Junk-Size $j; $after+=$j.Size; $it.SubItems[2].Text=Fmt-Size $j.Size; $lvJunk.Invalidate(); DE }
  Done; Update-JunkTotal
  $freed=[math]::Max(0,$before-$after)
  Log ("Freed {0}. Files in use were skipped." -f (Fmt-Size $freed)) $ac
  if($script:user){ $script:user.stats.cleaned+=$freed }; Add-History 'Clean up' "Freed $(Fmt-Size $freed)" }
$loaders['clean']={ Load-Junk }

# =========================================================
#  REMOVE APPS
# =========================================================
Step 'Building Remove apps...'
$pgRemove=New-Page 'remove' 'Remove apps' "Uninstall programs and built-in Windows apps you don't use."
$seg=Pnl $pgRemove 28 92 264 36 $pn 10
$segProg=Btn 'Programs' 3 3 128 30 { Set-RemoveTab 'prog' } 'secondary' $seg
$segWin=Btn 'Windows apps' 133 3 128 30 { Set-RemoveTab 'win' } 'secondary' $seg
[void](Btn 'Refresh' 472 92 110 36 { Load-Programs; Load-Bloat } 'secondary' $pgRemove)
[void](Btn 'Uninstall selected' 592 92 170 36 { if($script:remTab -eq 'prog'){ Uninstall-Programs }else{ Remove-Bloat } } 'primary' $pgRemove)
$lvProg=New-List $pgRemove 28 140 734 470 @(@('Name',290),@('Publisher',210),@('Size',90),@('Installed',0)) $true
$lvBloat=New-List $pgRemove 28 140 734 470 @(@('App',230),@('Package',0)) $true

function Set-RemoveTab($w){
  if($w -eq 'win'){ $lvBloat.Parent.Bounds=$lvProg.Parent.Bounds }else{ $lvProg.Parent.Bounds=$lvBloat.Parent.Bounds }
  $script:remTab=$w; $lvProg.Parent.Visible=($w -eq 'prog'); $lvBloat.Parent.Visible=($w -eq 'win')
  foreach($pair in @(@($segProg,'prog'),@($segWin,'win'))){
    $b=$pair[0]; $act=($pair[1] -eq $w)
    $b.BackColor=if($act){$pr}else{$pn}; $b.ForeColor=if($act){$white}else{$mu}
    $b.FlatAppearance.MouseOverBackColor=if($act){$prh}else{$hv}
    $script:fadeTo.Remove($b); $script:bcol.Remove($b); $b.Invalidate() } }
Set-RemoveTab 'prog'

function Load-Programs{
  Busy 'Reading installed programs...'; $lvProg.BeginUpdate(); $lvProg.Items.Clear()
  $keys='HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*','HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
  $apps=@(Get-ItemProperty $keys -ErrorAction SilentlyContinue | Where-Object {
    $_.DisplayName -and $_.UninstallString -and $_.SystemComponent -ne 1 -and -not $_.ParentKeyName -and $_.ReleaseType -notmatch 'Update|Hotfix' } |
    Sort-Object DisplayName -Unique)
  foreach($a in $apps){
    $sz=if($a.EstimatedSize){ Fmt-Size ([double]$a.EstimatedSize*1KB) }else{''}
    $dt=if("$($a.InstallDate)" -match '^(\d{4})(\d{2})(\d{2})$'){ "$($Matches[1])-$($Matches[2])-$($Matches[3])" }else{''}
    $it=Add-Row $lvProg @($a.DisplayName,$a.Publisher,$sz,$dt) $a; Set-CellColor $it 1 $mu }
  $lvProg.EndUpdate(); Done }

$bloat=[ordered]@{
  'Microsoft.BingNews'='News'; 'Microsoft.BingWeather'='Weather'; 'Microsoft.BingSearch'='Bing Search'
  'Microsoft.GetHelp'='Get Help'; 'Microsoft.Getstarted'='Tips'; 'Microsoft.MicrosoftSolitaireCollection'='Solitaire Collection'
  'Microsoft.People'='People'; 'Microsoft.WindowsFeedbackHub'='Feedback Hub'; 'Microsoft.WindowsMaps'='Maps'
  'Microsoft.ZuneMusic'='Media Player'; 'Microsoft.ZuneVideo'='Movies & TV'; 'Clipchamp.Clipchamp'='Clipchamp'
  'Microsoft.MicrosoftOfficeHub'='Microsoft 365 (Office) hub'; 'Microsoft.Todos'='Microsoft To Do'; 'Microsoft.SkypeApp'='Skype'
  'Microsoft.PowerAutomateDesktop'='Power Automate'; 'Microsoft.549981C3F5F10'='Cortana'; 'MicrosoftCorporationII.QuickAssist'='Quick Assist'
  'MicrosoftTeams'='Teams (personal)'; 'MSTeams'='Teams'; 'Microsoft.OutlookForWindows'='Outlook (new)'
  'Microsoft.Windows.DevHome'='Dev Home'; 'Microsoft.YourPhone'='Phone Link'; 'Microsoft.MixedReality.Portal'='Mixed Reality Portal'
  'Microsoft.Microsoft3DViewer'='3D Viewer'; 'Microsoft.MSPaint'='Paint 3D'; 'MicrosoftCorporationII.MicrosoftFamily'='Family'
  'Microsoft.WindowsAlarms'='Clock'; 'Microsoft.WindowsSoundRecorder'='Sound Recorder' }
function Load-Bloat{
  Busy 'Reading Windows apps...'; $lvBloat.BeginUpdate(); $lvBloat.Items.Clear()
  $pk=@(Get-AppxPackage -ErrorAction SilentlyContinue)
  foreach($k in $bloat.Keys){
    $m=$pk | Where-Object { $_.Name -eq $k } | Select-Object -First 1
    if($m){ $it=Add-Row $lvBloat @($bloat[$k],$m.Name) $m.PackageFullName; Set-CellColor $it 1 $mu } }
  if($lvBloat.Items.Count -eq 0){ [void](Add-Row $lvBloat @('Nothing left to remove','') $null $mu) }
  $lvBloat.EndUpdate(); Done }

function Uninstall-Programs{
  $sel=@(Get-Picked $lvProg); if(!$sel){ Log 'Tick the programs you want to remove first.' $warn; return }
  $names=($sel | ForEach-Object { $_.Tag.Data.DisplayName }) -join "`n"
  $a=[Windows.Forms.MessageBox]::Show("Uninstall these programs?`n`n$names`n`nEach uninstaller opens one at a time.",'Remove apps','YesNo','Question')
  if($a -ne 'Yes'){ return }
  foreach($it in $sel){ $d=$it.Tag.Data; $us=[string]$d.UninstallString
    if($us -match 'msiexec'){ $us=$us -replace '/I\s*\{','/X{' }
    if($us -match '^\s*"([^"]+)"\s*(.*)$'){ $exe=$Matches[1]; $arg=$Matches[2] }
    elseif($us -match '^\s*(.+?\.exe)\s*(.*)$'){ $exe=$Matches[1]; $arg=$Matches[2] }
    else{ $exe='cmd.exe'; $arg="/c $us" }
    Busy "Uninstalling $($d.DisplayName)..."
    try{
      $p=if($arg.Trim()){ Start-Process -FilePath $exe -ArgumentList $arg -PassThru }else{ Start-Process -FilePath $exe -PassThru }
      while(-not $p.HasExited){ DE; Start-Sleep -Milliseconds 150 }
      Log "Uninstaller finished: $($d.DisplayName)" $ac }
    catch{ Log "Couldn't start the uninstaller for $($d.DisplayName)." $bad } }
  Done; Load-Programs }

function Remove-Bloat{
  $sel=@(Get-Picked $lvBloat); if(!$sel){ Log 'Tick the Windows apps you want to remove first.' $warn; return }
  $names=($sel | ForEach-Object { $_.Text }) -join ', '
  $a=[Windows.Forms.MessageBox]::Show("Remove $($names)?`n`nYou can reinstall them from the Microsoft Store later.",'Remove apps','YesNo','Question')
  if($a -ne 'Yes'){ return }
  foreach($it in $sel){ Busy "Removing $($it.Text)..."
    try{ Remove-AppxPackage -Package $it.Tag.Data -Confirm:$false -ErrorAction Stop; Log "Removed $($it.Text)." $ac }
    catch{ Log "Couldn't remove $($it.Text)." $bad }; DE }
  Done; Load-Bloat }
$loaders['remove']={ Load-Programs; Load-Bloat }

# =========================================================
#  FORTNITE
# =========================================================
Step 'Building Fortnite page...'
$pgFn=New-Page 'fn' 'Fortnite' 'Real FPS and smoothness gains. Close Fortnite before you apply.'
[void](Btn 'Apply to Fortnite' 28 92 142 36 { Apply-Fortnite } 'primary' $pgFn)
[void](Btn 'Potato mode' 178 92 120 36 { Apply-Potato } 'card' $pgFn)
[void](Btn 'Restore' 306 92 90 36 { Restore-Fortnite } 'secondary' $pgFn)
$resLbl=Lbl '3D res' 406 100 9.5 $mu $false $pgFn
$resHost=Pnl $pgFn 452 92 90 36 $pn 10
$cbRes=New-Object Windows.Forms.ComboBox; $cbRes.Location=New-Object Drawing.Point(8,6); $cbRes.Size=New-Object Drawing.Size(74,26)
$cbRes.DropDownStyle='DropDownList'; $cbRes.FlatStyle='Flat'; $cbRes.BackColor=$pn; $cbRes.ForeColor=$tx; $cbRes.Font=$fUI
foreach($v in 100,90,85,80,75,67,50){ [void]$cbRes.Items.Add("$v%") }; $cbRes.SelectedIndex=0; $resHost.Controls.Add($cbRes)
function Get-Res{ [int](([string]$cbRes.SelectedItem) -replace '\D','') }
$capLbl=Lbl 'FPS cap' 552 100 9.5 $mu $false $pgFn
$capHost=Pnl $pgFn 608 92 154 36 $pn 10
$cbCap=New-Object Windows.Forms.ComboBox; $cbCap.Location=New-Object Drawing.Point(8,6); $cbCap.Size=New-Object Drawing.Size(138,26)
$cbCap.DropDownStyle='DropDownList'; $cbCap.FlatStyle='Flat'; $cbCap.BackColor=$pn; $cbCap.ForeColor=$tx; $cbCap.Font=$fUI
$capHost.Controls.Add($cbCap)
$fnSum=New-Summary $pgFn
$lvFn=New-List $pgFn 28 140 734 250 @(@('Fortnite setting',230),@('What it does',320),@('Now',0)) $true

$chkLbl=Lbl 'PC check' 27 404 11 $tx $true $pgFn
$vivBtn=Btn 'Vivid colors' 352 398 110 34 { Toggle-Vivid } 'card' $pgFn
$chkBtn=Btn 'Recheck' 472 398 110 34 { Load-PcCheck } 'secondary' $pgFn
[void](Btn 'Set max refresh rate' 592 398 170 34 {
  try{ $r=[FXNative]::SetMaxRefresh(); if($r -eq 0){ Log 'Your screen now runs at its highest refresh rate.' $ac }else{ Log "Windows refused the change (code $r)." $warn } }
  catch{ Log "Couldn't change the refresh rate." $bad }
  Load-PcCheck } 'secondary' $pgFn)
$lvChk=New-List $pgFn 28 440 734 170 @(@('Check',150),@('Result',300),@('Tip',0)) $false

$script:hz=60; try{ $script:hz=[math]::Max(60,[FXNative]::Refresh()[1]) }catch{}
function Update-CapList{
  $sel=$cbCap.SelectedIndex; $cbCap.Items.Clear()
  [void]$cbCap.Items.Add("Screen ($($script:hz))")
  [void]$cbCap.Items.Add('Unlimited')
  foreach($v in 60,120,144,165,240,360){ [void]$cbCap.Items.Add("$v FPS") }
  $cbCap.SelectedIndex=[math]::Max(0,$sel) }
Update-CapList
function Get-Cap{ $t=[string]$cbCap.SelectedItem
  if($t -like 'Screen*'){ $script:hz }elseif($t -like 'Unlimited*'){ 0 }else{ [int]($t -replace '\D','') } }

# ---- GameUserSettings.ini editing ----
function Find-FnIni{
  $rel='FortniteGame\Saved\Config\WindowsClient\GameUserSettings.ini'
  $cands=@()
  try{
    $ex=Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop | Select-Object -First 1
    $sid=(Invoke-CimMethod -InputObject $ex -MethodName GetOwnerSid -ErrorAction Stop).Sid
    $prof=(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\$sid" -ErrorAction Stop).ProfileImagePath
    if($prof){ $cands+=(Join-Path $prof "AppData\Local\$rel") } }catch{}
  $cands+=(Join-Path $env:LOCALAPPDATA $rel)
  foreach($c in $cands){ if(Test-Path $c){ return $c } }
  $cands[0] }
$FNINI=Find-FnIni
$script:fnOtherUser=-not $FNINI.StartsWith($env:LOCALAPPDATA,[StringComparison]::OrdinalIgnoreCase)
$FGS='/Script/FortniteGame.FortGameUserSettings'; $SGQ='ScalabilityGroups'; $RHI='D3DRHIPreference'
$INV=[Globalization.CultureInfo]::InvariantCulture
function Read-Ini{
  $l=New-Object 'System.Collections.Generic.List[string]'
  if(Test-Path $FNINI){ foreach($x in [IO.File]::ReadAllLines($FNINI)){ $l.Add($x) } }
  ,$l }
function Write-Ini($L){
  $b=[IO.File]::ReadAllBytes($FNINI)
  $enc=if($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE){ [Text.Encoding]::Unicode }else{ New-Object Text.UTF8Encoding($false) }
  [IO.File]::WriteAllLines($FNINI,[string[]]$L.ToArray(),$enc) }
function Find-Sec($L,$sec){
  for($i=0;$i -lt $L.Count;$i++){ if($L[$i].Trim() -eq "[$sec]"){
    $e=$L.Count; for($j=$i+1;$j -lt $L.Count;$j++){ if($L[$j].Trim().StartsWith('[')){ $e=$j; break } }
    return @($i,$e) } }
  $null }
function Get-Ini($L,$sec,$key){
  $r=Find-Sec $L $sec; if(-not $r){ return $null }
  for($j=$r[0]+1;$j -lt $r[1];$j++){ if($L[$j] -match "^\s*$([regex]::Escape($key))\s*=(.*)$"){ return $Matches[1].Trim() } }
  $null }
function Set-Ini($L,$sec,$key,$val){
  $r=Find-Sec $L $sec
  if(-not $r){ $L.Add(''); $L.Add("[$sec]"); $L.Add("$key=$val"); return }
  for($j=$r[0]+1;$j -lt $r[1];$j++){ if($L[$j] -match "^\s*$([regex]::Escape($key))\s*="){ $L[$j]="$key=$val"; return } }
  $at=$r[1]; while($at -gt $r[0]+1 -and $L[$at-1].Trim() -eq ''){ $at-- }
  $L.Insert($at,"$key=$val") }
function OnOff($b){ if($b){'On'}else{'Off'} }

function Set-Potato($L){
  Set-Ini $L $RHI 'PreferredFeatureLevel' 'es31'
  foreach($k in 'sg.AntiAliasingQuality','sg.ShadowQuality','sg.GlobalIlluminationQuality','sg.ReflectionQuality',
                 'sg.PostProcessQuality','sg.TextureQuality','sg.EffectsQuality','sg.FoliageQuality','sg.ShadingQuality'){ Set-Ini $L $SGQ $k 0 }
  Set-Ini $L $SGQ 'sg.ViewDistanceQuality' 2
  Set-Ini $L $SGQ 'sg.ResolutionQuality' (100.0).ToString('F6',$INV)
  Set-Ini $L 'PerformanceMode' 'MeshQuality' 0
  Set-Ini $L $FGS 'bUseVSync' 'False'; Set-Ini $L $FGS 'bMotionBlur' 'False'; Set-Ini $L $FGS 'bShowFPS' 'True' }
function Test-Potato($L){
  (Get-Ini $L $SGQ 'sg.TextureQuality') -eq '0' -and (Get-Ini $L $SGQ 'sg.FoliageQuality') -eq '0' -and
  (Get-Ini $L $SGQ 'sg.EffectsQuality') -eq '0' -and (Get-Ini $L 'PerformanceMode' 'MeshQuality') -eq '0' }
function FS($name,$desc,$rec,$now,$apply){ [pscustomobject]@{Name=$name;Desc=$desc;Rec=$rec;Now=$now;Apply=$apply} }
$fnSet=@(
  (FS 'Performance rendering mode' 'Biggest FPS boost by far (simpler graphics)' $true { param($L) OnOff ((Get-Ini $L $RHI 'PreferredFeatureLevel') -eq 'es31') } { param($L) Set-Ini $L $RHI 'PreferredFeatureLevel' 'es31' }),
  (FS 'Competitive graphics' 'Shadows, effects, foliage, post-processing low' $true { param($L) OnOff ((Get-Ini $L $SGQ 'sg.ShadowQuality') -eq '0' -and (Get-Ini $L $SGQ 'sg.EffectsQuality') -eq '0') } { param($L) foreach($k in 'sg.ShadowQuality','sg.EffectsQuality','sg.FoliageQuality','sg.PostProcessQuality','sg.GlobalIlluminationQuality','sg.ReflectionQuality'){ Set-Ini $L $SGQ $k 0 } Set-Ini $L $SGQ 'sg.ViewDistanceQuality' 2 }),
  (FS 'FPS cap' 'Steady frame times: pick the cap above' $true { param($L) $v=Get-Ini $L $FGS 'FrameRateLimit'; if(-not $v){ 'Not set' }else{ $n=[double]::Parse($v,$INV); if($n -eq 0){ 'Unlimited' }else{ "$([int]$n) FPS" } } } { param($L) Set-Ini $L $FGS 'FrameRateLimit' ([double](Get-Cap)).ToString('F6',$INV) }),
  (FS 'VSync off' 'Removes up to a frame of input delay' $true { param($L) OnOff ((Get-Ini $L $FGS 'bUseVSync') -eq 'False') } { param($L) Set-Ini $L $FGS 'bUseVSync' 'False' }),
  (FS 'Motion blur off' 'Clearer picture when you turn fast' $true { param($L) OnOff ((Get-Ini $L $FGS 'bMotionBlur') -eq 'False') } { param($L) Set-Ini $L $FGS 'bMotionBlur' 'False' }),
  (FS 'Show FPS counter' 'See your FPS while you play' $true { param($L) OnOff ((Get-Ini $L $FGS 'bShowFPS') -eq 'True') } { param($L) Set-Ini $L $FGS 'bShowFPS' 'True' }),
  (FS 'Anti-aliasing off' 'Small FPS gain and sharper edges' $true { param($L) OnOff ((Get-Ini $L $SGQ 'sg.AntiAliasingQuality') -eq '0') } { param($L) Set-Ini $L $SGQ 'sg.AntiAliasingQuality' 0 }),
  (FS 'Low textures' 'For 4 GB video memory or less (blurrier skins)' $false { param($L) OnOff ((Get-Ini $L $SGQ 'sg.TextureQuality') -eq '0') } { param($L) Set-Ini $L $SGQ 'sg.TextureQuality' 0 }),
  (FS '3D resolution' 'Lower = more FPS but blurrier: pick it above' $false { param($L) $v=Get-Ini $L $SGQ 'sg.ResolutionQuality'; if($v){ "$([int][double]::Parse($v,$INV))%" }else{ 'Not set' } } { param($L) Set-Ini $L $SGQ 'sg.ResolutionQuality' ([double](Get-Res)).ToString('F6',$INV) }),
  (FS 'Lock settings' "Stops Fortnite resetting them (in-game changes won't save)" $false { param($L) OnOff ((Test-Path $FNINI) -and (Get-Item $FNINI).IsReadOnly) } { param($L) })
)

function Load-FnSettings{
  $keep=@{}; foreach($it in $lvFn.Items){ $keep[$it.Text]=$it.Tag.On }
  $lvFn.BeginUpdate(); $lvFn.Items.Clear()
  $L=Read-Ini; $have=(Test-Path $FNINI)
  foreach($s0 in $fnSet){
    $now=if($have){ try{ & $s0.Now $L }catch{ '?' } }else{ 'No file yet' }
    $on=if($keep.ContainsKey($s0.Name)){ $keep[$s0.Name] }else{ $s0.Rec }
    $it=Add-Row $lvFn @($s0.Name,$s0.Desc,$now) $s0 $tx $on
    Set-CellColor $it 1 $mu; Set-CellColor $it 2 $(if($now -in 'Off','Not set','No file yet','?'){ $mu }else{ $okc }) }
  $lvFn.EndUpdate()
  $n=@($lvFn.Items | Where-Object { $_.SubItems[2].Text -notin 'Off','Not set','No file yet','?' }).Count
  Set-Summary $fnSum $n $lvFn.Items.Count 'Fortnite settings' }
function Apply-Fortnite{
  if(Get-Process -Name $FN -ErrorAction SilentlyContinue){ Log 'Close Fortnite first: it overwrites its settings when it closes.' $warn; return }
  if(-not (Test-Path $FNINI)){ Log 'No Fortnite settings file yet. Start Fortnite once, close it, then try again.' $warn; return }
  $sel=@(Get-Picked $lvFn); if(!$sel){ Log 'Tick the Fortnite settings you want first.' $warn; return }
  Save-Snapshot 'Before Fortnite settings' $true
  try{
    $bak="$FNINI.fxbackup"; if(-not (Test-Path $bak)){ Copy-Item $FNINI $bak -Force }
    $fi=Get-Item $FNINI; if($fi.IsReadOnly){ $fi.IsReadOnly=$false }
    $L=Read-Ini
    foreach($it in $sel){ & $it.Tag.Data.Apply $L }
    Write-Ini $L
    $lock=@($sel | Where-Object { $_.Tag.Data.Name -eq 'Lock settings' }).Count -gt 0
    if($lock){ (Get-Item $FNINI).IsReadOnly=$true; Log 'Settings locked. To change settings in Fortnite again, apply here without Lock ticked.' }
    Log "Applied $($sel.Count) Fortnite settings. Start Fortnite to use them." $ac
    if($script:user){ $script:user.cap=$cbCap.SelectedIndex; $script:user.stats.fnApplies++ }; Add-History 'Fortnite settings' "$($sel.Count) settings applied"
    Log 'Tip: if Fortnite shows another Rendering Mode, pick Performance once in its Video settings.'
    Log 'Extra: in the Epic launcher, Library > Fortnite > ... > Options, untick High Resolution Textures to save 15+ GB.' }
  catch{ Log "Couldn't save Fortnite settings: $($_.Exception.Message)" $bad }
  Load-FnSettings }
$nvCode=@"
using System;
using System.Runtime.InteropServices;
public static class FXNv {
  [DllImport("nvapi64.dll", EntryPoint = "nvapi_QueryInterface", CallingConvention = CallingConvention.Cdecl)] static extern IntPtr QI(uint id);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int InitD();
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int EnumD(int i, out IntPtr h);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SetD(IntPtr h, uint output, int level);
  [StructLayout(LayoutKind.Sequential)] struct DVC { public uint version; public int cur; public int min; public int max; }
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int GetD(IntPtr h, uint output, ref DVC info);
  static Delegate F(uint id, Type t){ IntPtr p = QI(id); return p == IntPtr.Zero ? null : Marshal.GetDelegateForFunctionPointer(p, t); }
  // percent: 50 = normal (NVIDIA default), 100 = maximum. Returns number of screens changed, or negative on failure.
  public static int SetVibrance(int percent){
    InitD init = (InitD)F(0x0150E828, typeof(InitD)); if(init == null || init() != 0) return -1;
    EnumD en = (EnumD)F(0x9ABDD40D, typeof(EnumD)); SetD set = (SetD)F(0x172409B4, typeof(SetD)); GetD get = (GetD)F(0x4085DE45, typeof(GetD));
    if(en == null || set == null) return -2;
    int n = 0; IntPtr h;
    for(int i = 0; i < 8 && en(i, out h) == 0; i++){
      int max = 63;
      if(get != null){ DVC d = new DVC(); d.version = (uint)(Marshal.SizeOf(typeof(DVC)) | (1 << 16)); if(get(h, 0, ref d) == 0 && d.max > 0) max = d.max; }
      int level = (int)Math.Round((percent - 50) / 50.0 * max); if(level < 0) level = 0; if(level > max) level = max;
      if(set(h, 0, level) == 0) n++; }
    return n; }
}

"@
function Set-Vivid($pct,[switch]$quiet){
  if((RegGet 'HKCU:\Software\FXTweaks' VibranceTrying) -eq 1){
    RegSet 'HKCU\Software\FXTweaks' Vibrance 50; RegSet 'HKCU\Software\FXTweaks' VibranceTrying 0
    if(-not $quiet){ Log 'Vivid colors crashed last time, so it is turned off on this PC. Use NVIDIA Control Panel > Digital Vibrance instead.' $warn }
    return $false }
  try{
    if(-not ('FXNv' -as [type])){ Add-Type -TypeDefinition $nvCode -ErrorAction Stop }
    RegSet 'HKCU\Software\FXTweaks' VibranceTrying 1
    $n=[FXNv]::SetVibrance($pct)
    RegSet 'HKCU\Software\FXTweaks' VibranceTrying 0
    if($n -gt 0){ if(-not $quiet){ Log $(if($pct -gt 50){ "Vivid colors on ($pct%)." }else{ 'Colors back to normal.' }) $ac }; return $true }
    if(-not $quiet){ Log 'Could not change colors on this NVIDIA card.' $warn } }
  catch{ RegSet 'HKCU\Software\FXTweaks' VibranceTrying 0
    if(-not $quiet){ Log 'Vivid colors works on NVIDIA cards. AMD: Radeon Software > Display > Saturation (about 130-150). Intel: Graphics Command Center > Display > Color > Saturation.' $warn } }
  $false }
function Toggle-Vivid{
  $cur=RegGet 'HKCU:\Software\FXTweaks' Vibrance
  $new=if($cur -and [int]$cur -gt 50){ 50 }else{ 80 }
  if(Set-Vivid $new){ RegSet 'HKCU\Software\FXTweaks' Vibrance $new; Add-History 'Vivid colors' "$new%" } }

# ---- NVIDIA potato: driver texture settings for the Fortnite profile, via NVIDIA Profile Inspector ----
$NPI_URL='https://github.com/Orbmu2k/nvidiaProfileInspector/releases/download/v3.0.2.1/nvidiaProfileInspector.zip'
$NPI_DIR=Join-Path $env:LOCALAPPDATA 'FX Tweaks\nvidiaProfileInspector'
$NPI_EXE=Join-Path $NPI_DIR 'nvidiaProfileInspector.exe'
function Get-Npi{
  if(Test-Path $NPI_EXE){ return $true }
  Busy 'Downloading NVIDIA Profile Inspector (about 0.5 MB)...'
  try{
    New-Item -ItemType Directory $NPI_DIR -Force | Out-Null
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    $zip=Join-Path $env:TEMP 'fx_npi.zip'
    (New-Object Net.WebClient).DownloadFile($NPI_URL,$zip)
    Expand-Archive -LiteralPath $zip -DestinationPath $NPI_DIR -Force
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }
  catch{ Done; Log "Couldn't download NVIDIA Profile Inspector: $($_.Exception.Message)" $bad; return $false }
  Done; Test-Path $NPI_EXE }
function Run-Npi($argList){
  $p=Start-Process -FilePath $NPI_EXE -ArgumentList $argList -WorkingDirectory $NPI_DIR -PassThru
  $t=[Diagnostics.Stopwatch]::StartNew()
  while(-not $p.HasExited -and $t.Elapsed.TotalSeconds -lt 45){ DE; Start-Sleep -Milliseconds 150 }
  $p.HasExited }
function New-Nip($settings){
  # $settings: ordered list of @(name, id, value)
  $rows=foreach($x in $settings){
"      <ProfileSetting>
        <SettingNameInfo>$($x[0])</SettingNameInfo>
        <SettingID>$($x[1])</SettingID>
        <SettingValue>$($x[2])</SettingValue>
        <ValueType>Dword</ValueType>
      </ProfileSetting>" }
@"
<?xml version="1.0" encoding="utf-8"?>
<ArrayOfProfile>
  <Profile>
    <ProfileName>Fortnite</ProfileName>
    <Executeables>
      <string>fortniteclient-win64-shipping.exe</string>
    </Executeables>
    <Settings>
$($rows -join "`r`n")
    </Settings>
  </Profile>
</ArrayOfProfile>
"@ }
# The potato values (copied from the user's Profile Inspector screenshots):
#   LOD Bias (DX)  0x00738E8F = 0x45 (69)      LOD Bias (OGL) 0x20403F79 = 0x45 (69)
#   Texture filtering Quality 0x00CE2691 = High quality (0xFFFFFFF6)
#   Transparency Supersampling 0x10D48A85 = 8x Sparse Grid Supersampling (0x38)
#   Driver Controlled LOD Bias 0x00638E8F = Off
$NV_POTATO=@(
  @('Texture filtering - Driver Controlled LOD Bias',6524559,0),
  @('Texture Filtering - LOD Bias (DX)',7573135,69),
  @('Texture Filtering - LOD Bias (OGL)',541081465,69),
  @('Texture Filtering - Quality',13510289,4294967286),
  @('Antialiasing - Transparency Supersampling',282364549,56))
$NV_NORMAL=@(
  @('Texture filtering - Driver Controlled LOD Bias',6524559,1),
  @('Texture Filtering - LOD Bias (DX)',7573135,0),
  @('Texture Filtering - LOD Bias (OGL)',541081465,0),
  @('Texture Filtering - Quality',13510289,0),
  @('Antialiasing - Transparency Supersampling',282364549,0))
function Test-NpiExport($wantLod){
  # export all customized profiles, then look for Fortnite with our LOD bias value
  Get-ChildItem -LiteralPath $NPI_DIR -Filter 'CustomProfiles_*.nip' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
  if(-not (Run-Npi @('-exportCustomized'))){ return $null }
  $exp=Get-ChildItem -LiteralPath $NPI_DIR -Filter 'CustomProfiles_*.nip' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if(-not $exp){ return $null }
  try{ [xml]$x=[IO.File]::ReadAllText($exp.FullName) }catch{ return $null }
  foreach($pr in @($x.ArrayOfProfile.Profile)){
    $exes=@($pr.Executeables.string) | ForEach-Object { "$_".ToLower() }
    if($exes -notcontains 'fortniteclient-win64-shipping.exe'){ continue }
    $lod=@($pr.Settings.ProfileSetting) | Where-Object { $_.SettingID -eq '7573135' } | Select-Object -First 1
    $val=if($lod){ [string]$lod.SettingValue }else{ '0' }
    return ($val -eq "$wantLod") }
  $false }
function Set-NvPotato($on){
  try{ $gpu=@(Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name -match 'NVIDIA' }) }catch{ $gpu=@() }
  if(-not $gpu.Count){ Log 'NVIDIA potato needs an NVIDIA graphics card. On AMD or Intel, use Potato mode and Vivid colors instead.' $warn; return $false }
  if(-not (Get-Npi)){ return $false }
  $nip=Join-Path $NPI_DIR $(if($on){ 'fx_potato.nip' }else{ 'fx_normal.nip' })
  $content=if($on){ New-Nip $NV_POTATO }else{ New-Nip $NV_NORMAL }
  [IO.File]::WriteAllText($nip,$content,(New-Object Text.UTF8Encoding($false)))
  $st.Text=if($on){ 'Turning on NVIDIA potato...' }else{ 'Turning off NVIDIA potato...' }; DE
  $done=Run-Npi @('-silentImport','-mergeImport',"`"$nip`"")
  $ok=if($done){ Test-NpiExport $(if($on){ 69 }else{ 0 }) }else{ $null }
  if($ok -eq $true){
    RegSet 'HKCU\Software\FXTweaks' NvPotato $(if($on){ 1 }else{ 0 })
    Log $(if($on){ 'NVIDIA potato is on and checked. Restart Fortnite to see the flat textures.' }else{ 'NVIDIA potato is off. Restart Fortnite to see normal textures.' }) $ac
    return $true }
  Log "Couldn't confirm the NVIDIA change automatically, so Profile Inspector is opening for you." $warn
  Log 'In it: type Fortnite in the Profiles box, set LOD Bias (DX) and LOD Bias (OGL) = 0x00000045, Texture Filtering Quality = High quality, Transparency Supersampling = 8x Sparse Grid Supersampling, then Apply changes.' $warn
  try{ Start-Process -FilePath $NPI_EXE -WorkingDirectory $NPI_DIR }catch{}
  $false }

function Apply-Potato{
  $a=[Windows.Forms.MessageBox]::Show("Potato mode gives Fortnite the flat pro look: Performance mode, lowest textures and models, no grass, no shadows or effects.`n`nThe picture stays sharp (100% resolution) and you can still see far.`n`nYou can go back anytime with Restore or on the Profiles page.",'Potato mode','YesNo','Question')
  if($a -ne 'Yes'){ return }
  if(Get-Process -Name $FN -ErrorAction SilentlyContinue){ Log 'Close Fortnite first: it overwrites its settings when it closes.' $warn; return }
  if(-not (Test-Path $FNINI)){ Log 'No Fortnite settings file yet. Start Fortnite once, close it, then try again.' $warn; return }
  Save-Snapshot 'Before Potato mode' $true
  try{
    $bak="$FNINI.fxbackup"; if(-not (Test-Path $bak)){ Copy-Item $FNINI $bak -Force }
    $fi=Get-Item $FNINI; if($fi.IsReadOnly){ $fi.IsReadOnly=$false }
    $L=Read-Ini; Set-Potato $L; Write-Ini $L
    $cbRes.SelectedItem='100%'
    if(Test-Potato (Read-Ini)){ Log 'Potato mode saved and checked. Start Fortnite (fully restart it if it was open) to see it.' $ac }else{ Log "Potato settings didn't stick in $FNINI" $bad }
    Log 'The flat look only shows in Performance mode: if the ground still has detail, set Fortnite > Settings > Video > Rendering Mode to Performance once.'
    Log 'Want even more FPS? Pick a lower 3D res above and apply with only 3D resolution ticked.'
    Add-History 'Potato mode' 'Flat pro look' }
  catch{ Log "Couldn't save Fortnite settings: $($_.Exception.Message)" $bad }
  Load-FnSettings }

function Restore-Fortnite{
  $bak="$FNINI.fxbackup"
  if(-not (Test-Path $bak)){ Log 'No backup yet: FX Tweaks makes one the first time you apply.' $warn; return }
  if(Get-Process -Name $FN -ErrorAction SilentlyContinue){ Log 'Close Fortnite first.' $warn; return }
  try{ (Get-Item $FNINI).IsReadOnly=$false }catch{}
  Copy-Item $bak $FNINI -Force; try{ (Get-Item $FNINI).IsReadOnly=$false }catch{}
  Log 'Your original Fortnite settings are back (and unlocked).' $ac; Load-FnSettings }

# ---- PC check ----
function Chk($name,$result,$ok,$tip){
  $it=Add-Row $lvChk @($name,$result,$tip) $name
  Set-CellColor $it 1 $(if($ok -eq $true){ $okc }elseif($ok -eq $false){ $warn }else{ $tx }); Set-CellColor $it 2 $mu }
function Load-PcCheck{
  Busy 'Checking your PC...'; $lvChk.BeginUpdate(); $lvChk.Items.Clear()
  try{ $rr=[FXNative]::Refresh(); $script:hz=[math]::Max(60,$rr[1])
    if($rr[0] -lt $rr[1]){ Chk 'Refresh rate' "$($rr[0]) Hz (your screen can do $($rr[1]) Hz)" $false "Click 'Set max refresh rate'" }
    else{ Chk 'Refresh rate' "$($rr[0]) Hz" $true 'Fastest your screen supports' } }catch{ Chk 'Refresh rate' 'Unknown' $null '' }
  try{ $ps=[Windows.Forms.SystemInformation]::PowerStatus
    if("$($ps.BatteryChargeStatus)" -match 'NoSystemBattery'){ Chk 'Power' 'Desktop PC' $true 'Always full power' }
    elseif("$($ps.PowerLineStatus)" -eq 'Offline'){ Chk 'Power' 'Laptop on battery' $false 'Plug in for full FPS' }
    else{ Chk 'Power' 'Laptop plugged in' $true 'Full power available' } }catch{}
  try{
    $gpus=@(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -notmatch 'Basic|Remote|Virtual|Meta|Parsec' })
    $ded=$gpus | Where-Object { $_.Name -match 'NVIDIA|AMD|Radeon|Arc' } | Select-Object -First 1
    $g=if($ded){ $ded }else{ $gpus | Select-Object -First 1 }
    $age=if($g.DriverDate){ [int]((Get-Date)-$g.DriverDate).TotalDays }else{ 0 }
    if(-not $ded){ Chk 'Graphics' $g.Name $null 'Built-in graphics: Performance mode matters most' }
    elseif($age -gt 180){ Chk 'Graphics' $g.Name $false "Driver is $([int]($age/30)) months old: update it" }
    else{ Chk 'Graphics' $g.Name $true 'Driver is recent' } }catch{}
  try{
    $rt=Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Sort-Object RouteMetric | Select-Object -First 1
    $ad=Get-NetAdapter -InterfaceIndex $rt.ifIndex -ErrorAction Stop
    if("$($ad.PhysicalMediaType)" -match '802\.11' -or $ad.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN'){ Chk 'Connection' "Wi-Fi ($($ad.LinkSpeed))" $false 'An Ethernet cable gives lower, steadier ping' }
    else{ Chk 'Connection' "Ethernet ($($ad.LinkSpeed))" $true 'Best for stable ping' } }catch{ Chk 'Connection' 'Not connected' $false '' }
  try{
    $mem=@(Get-CimInstance Win32_PhysicalMemory); $gb=[math]::Round(($mem | Measure-Object Capacity -Sum).Sum/1GB)
    $spd=($mem | Where-Object { $_.ConfiguredClockSpeed } | Select-Object -First 1).ConfiguredClockSpeed
    $tip=if($gb -lt 16){ '16 GB or more helps with stutters' }elseif($mem.Count -eq 1){ '1 stick runs single channel: 2 sticks are faster' }else{ 'If your RAM is rated faster, turn on XMP/EXPO in BIOS' }
    Chk 'Memory' "$gb GB, $($mem.Count) stick(s), $spd MT/s" ($gb -ge 16 -and $mem.Count -ge 2) $tip }catch{}
  try{
    $drv=if($script:fnExe){ $script:fnExe.Substring(0,1) }else{ $env:SystemDrive.Substring(0,1) }
    $free=(Get-Volume -DriveLetter $drv -ErrorAction Stop).SizeRemaining
    $media=''; try{ $dn=(Get-Partition -DriveLetter $drv -ErrorAction Stop).DiskNumber
      $media="$((Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq "$dn" } | Select-Object -First 1).MediaType)" }catch{}
    $hdd=($media -eq 'HDD')
    $tip=if($hdd){ 'Hard drive: move Fortnite to an SSD to stop stutters' }elseif($free -lt 20GB){ 'Low space: use the Clean up files page' }else{ 'Plenty of space' }
    Chk 'Fortnite drive' ("$($drv): $(Fmt-Size $free) free" + $(if($media -and $media -ne 'Unspecified'){ " ($media)" }else{ '' }))  ((-not $hdd) -and $free -gt 20GB) $tip }catch{}
  try{
    if(Test-Path $FNINI){
      $Lc=Read-Ini; $pot=Test-Potato $Lc; $perf=((Get-Ini $Lc $RHI 'PreferredFeatureLevel') -eq 'es31')
      $res="Found" + $(if($pot){ ', Potato ON' }elseif($perf){ ', Performance mode' }else{ '' })
      Chk 'Fortnite settings' $res $true $FNINI }
    else{ Chk 'Fortnite settings' 'Not found' $false 'Start Fortnite once, close it, then click Recheck' } }catch{}
  try{ $cpu=Get-CimInstance Win32_Processor | Select-Object -First 1; Chk 'Processor' $cpu.Name.Trim() $null "$($cpu.NumberOfCores) cores, $($cpu.NumberOfLogicalProcessors) threads" }catch{}
  $lvChk.EndUpdate(); Update-CapList; Done }
$loaders['fn']={ Load-FnSettings; Load-PcCheck }

# =========================================================
#  ACCOUNTS (stored on this PC, passwords hashed with PBKDF2)
# =========================================================
Step 'Loading accounts...'
$ACCT_DIR=Join-Path $env:LOCALAPPDATA 'FX Tweaks'; $ACCT_FILE=Join-Path $ACCT_DIR 'accounts.json'
$script:user=$null; $script:fails=0; $script:lockUntil=$null; $script:lmode='signin'
function Now-Str{ Get-Date -Format 'yyyy-MM-dd HH:mm' }
function Load-Accounts{
  $d=$null; try{ if(Test-Path $ACCT_FILE){ $d=[IO.File]::ReadAllText($ACCT_FILE) | ConvertFrom-Json } }catch{}
  [pscustomobject]@{ remember=[string]$d.remember; users=[object[]]@($d.users | Where-Object { $_ }) } }
function Save-Accounts{
  try{ New-Item -ItemType Directory $ACCT_DIR -Force | Out-Null
    [IO.File]::WriteAllText($ACCT_FILE,(ConvertTo-Json -InputObject $script:acct -Depth 6),(New-Object Text.UTF8Encoding($false))) }
  catch{ Log "Couldn't save account data: $($_.Exception.Message)" $bad } }
function New-Salt{ $b=New-Object byte[] 16; (New-Object Security.Cryptography.RNGCryptoServiceProvider).GetBytes($b); [Convert]::ToBase64String($b) }
function Hash-Pw($pw,$salt){
  $sb2=[Convert]::FromBase64String($salt)
  try{ $k=New-Object Security.Cryptography.Rfc2898DeriveBytes($pw,$sb2,100000,[Security.Cryptography.HashAlgorithmName]::SHA256) }
  catch{ $k=New-Object Security.Cryptography.Rfc2898DeriveBytes($pw,$sb2,100000) }
  $h=[Convert]::ToBase64String($k.GetBytes(32)); $k.Dispose(); $h }
function Find-User($n){ $script:acct.users | Where-Object { $_.name -ieq $n } | Select-Object -First 1 }
$script:acct=Load-Accounts

function Add-History($kind,$result){
  if(-not $script:user){ return }
  $e=[pscustomobject]@{ date=(Now-Str); kind=$kind; result=$result }
  $script:user.history=[object[]](@($e)+@($script:user.history) | Select-Object -First 40)
  Save-Accounts; Refresh-Account }
function Add-Stat($name,$by=1){ if(-not $script:user){ return }; $script:user.stats.$name+=$by; Save-Accounts; Refresh-Account }

# ---- Account page ----
$pgAcct=New-Page 'acct' 'Account' 'Your profile, stats and history. Saved on this PC.'
$acCard=Pnl $pgAcct 28 92 734 110 $pn 16
$av=New-Object Windows.Forms.Panel; $av.Location=New-Object Drawing.Point(20,23); $av.Size=New-Object Drawing.Size(64,64); $av.BackColor=$pn
DoubleBuffer $av; $acCard.Controls.Add($av)
$av.Add_Paint({ try{
  $g=$_.Graphics; $g.SmoothingMode='AntiAlias'; $g.TextRenderingHint='AntiAlias'
  $g.FillEllipse((Br $pr),0,0,($this.Width-1),($this.Height-1))
  $ch=if($script:user){ $script:user.name.Substring(0,1).ToUpper() }else{ '?' }
  $fnt=New-Object Drawing.Font('Segoe UI Semibold',[single]($this.Height*0.42),[Drawing.GraphicsUnit]::Pixel)
  $sf2=New-Object Drawing.StringFormat; $sf2.Alignment='Center'; $sf2.LineAlignment='Center'
  $g.DrawString($ch,$fnt,[Drawing.Brushes]::White,(New-Object Drawing.RectangleF(0,0,$this.Width,$this.Height)),$sf2); $fnt.Dispose() }catch{} })
$acName=Lbl '' 100 24 15 $tx $true $acCard
$acSub=Lbl '' 102 62 9 $mu $false $acCard
$acPw=Btn 'Change password' 434 35 140 40 { Change-Password } 'card' $acCard
$acOut=Btn 'Sign out' 584 35 130 40 { Sign-Out } 'card' $acCard
$acIn=Btn 'Sign in' 584 35 130 40 { Show-Login } 'primary' $acCard
function StatCard($x,$label){ $c=Pnl $pgAcct $x 220 175 84 $pn 14; $v=Lbl '0' 18 12 18 $tx $true $c; [void](Lbl $label 20 52 9 $mu $false $c); $v }
$stBoost=StatCard 28 'Boosts applied'
$stPing=StatCard 214 'Ping tests'
$stBest=StatCard 400 'Best ping'
$stClean=StatCard 587 'Space cleaned'
[void](Lbl 'History' 27 322 11 $tx $true $pgAcct)
$lvHist=New-List $pgAcct 28 350 734 210 @(@('When',160),@('What',200),@('Result',0)) $false
$acDel=Btn 'Delete account' 612 574 150 34 { Delete-Account } 'secondary' $pgAcct
[void](Btn 'Check for updates' 28 574 170 34 {
  Log 'Checking GitHub for a newer version...'
  $script:updating=$false; Check-Update
  if($script:updating){ Log 'Update found. FX Tweaks will restart in a moment...' $ac; Start-Sleep -Milliseconds 400; $f.Close() }
  else{ Log "You already have the newest version (v$FX_VERSION)." $ac } } 'secondary' $pgAcct)

function Refresh-Account{
  $u=$script:user
  if($u){
    $acName.Text=$u.name; $acSub.Text="Member since $($u.created.Substring(0,10))   |   Last sign-in $($u.last)"
    $stBoost.Text="$($u.stats.boosts)"; $stPing.Text="$($u.stats.pings)"
    $stBest.Text=if($u.stats.best -gt 0){ "$($u.stats.best) ms" }else{ '-' }
    $stClean.Text=Fmt-Size ([double]$u.stats.cleaned)
    $acPw.Visible=$true; $acOut.Visible=$true; $acIn.Visible=$false; $acDel.Visible=$true; $userLbl.Text=$u.name }
  else{
    $acName.Text='Guest'; $acSub.Text='Sign in to save your stats, history and settings.'
    foreach($l in $stBoost,$stPing,$stBest,$stClean){ $l.Text='-' }
    $acPw.Visible=$false; $acOut.Visible=$false; $acIn.Visible=$true; $acDel.Visible=$false; $userLbl.Text='Guest' }
  $lvHist.BeginUpdate(); $lvHist.Items.Clear()
  if($u){ foreach($h in @($u.history)){ $it=Add-Row $lvHist @($h.date,$h.kind,$h.result) $h; Set-CellColor $it 0 $mu } }
  $lvHist.EndUpdate(); $av.Invalidate() }
$loaders['acct']={ Refresh-Account }

# ---- Login screen (covers the whole window) ----
$ov=New-Object Windows.Forms.Panel; $ov.Dock='Fill'; $ov.BackColor=$bg; DoubleBuffer $ov; $f.Controls.Add($ov)
$lc=Pnl $ov 0 0 400 470 $pn 18
$lLogo=New-Object Windows.Forms.PictureBox; $lLogo.Location=New-Object Drawing.Point(172,28); $lLogo.Size=New-Object Drawing.Size(56,56)
$lLogo.Image=New-FXBitmap (Px 112); $lLogo.SizeMode='Zoom'; $lLogo.Tag='center'; $lc.Controls.Add($lLogo)
$lTitle=Lbl 'Welcome to FX Tweaks' 0 92 15 $tx $true $lc; $lTitle.Tag='center'
$lSub=Lbl 'Your account is saved on this PC.' 0 124 9 $mu $false $lc; $lSub.Tag='center'
$lSeg=Pnl $lc 30 152 340 38 $bg 10
$tabIn=Btn 'Sign in' 3 3 166 32 { Set-LoginMode 'signin' } 'secondary' $lSeg
$tabNew=Btn 'Create account' 171 3 166 32 { Set-LoginMode 'create' } 'secondary' $lSeg
function Field($parent,$x,$y,$w,$pw){
  $h=Pnl $parent $x $y $w 38 $bg 10
  $t=New-Object Windows.Forms.TextBox; $t.BorderStyle='None'; $t.Location=New-Object Drawing.Point(12,10); $t.Width=$w-24
  $t.BackColor=$bg; $t.ForeColor=$tx; $t.Font=$fUI; if($pw){ $t.UseSystemPasswordChar=$true }
  $h.Controls.Add($t); $h.Cursor='IBeam'; $h.Add_Click({ $this.Controls[0].Focus() })
  $t.Add_Enter({ $this.BackColor=$hot; Fade-To $this.Parent $hot })
  $t.Add_Leave({ $this.BackColor=$bg; Fade-To $this.Parent $bg })
  $t }
$lU=Lbl 'Username' 30 204 9 $mu $false $lc;            $tbUser=Field $lc 30 224 340 $false
$lP=Lbl 'Password' 30 270 9 $mu $false $lc;            $tbPw=Field $lc 30 290 340 $true
$lConf=Lbl 'Confirm password' 30 336 9 $mu $false $lc; $tbPw2=Field $lc 30 356 340 $true
$cbRem=New-Object Windows.Forms.CheckBox; $cbRem.Text='Remember me'; $cbRem.AutoSize=$true; $cbRem.Location=New-Object Drawing.Point(30,340)
$cbRem.FlatStyle='Flat'; $cbRem.FlatAppearance.BorderColor=$bd; $cbRem.FlatAppearance.CheckedBackColor=$pr; $cbRem.ForeColor=$tx; $cbRem.Font=$fRow; $cbRem.Checked=$true
$lc.Controls.Add($cbRem)
$btnLogin=Btn 'Sign in' 30 372 340 42 { Do-Login } 'primary' $lc
$lErr=Lbl '' 30 422 9 $bad $false $lc
$lGuest=New-Object Windows.Forms.LinkLabel; $lGuest.Text='Continue without an account'; $lGuest.AutoSize=$true; $lGuest.Font=$fRow
$lGuest.LinkColor=$ac; $lGuest.ActiveLinkColor=$white; $lGuest.LinkBehavior='HoverUnderline'; $lGuest.Location=New-Object Drawing.Point(0,440); $lGuest.Tag='center'
$lGuest.Add_LinkClicked({ Continue-Guest }); $lc.Controls.Add($lGuest)

function Center-Login{
  $lc.Left=[int][math]::Max(0,($ov.ClientSize.Width-$lc.Width)/2); $lc.Top=[int][math]::Max(0,($ov.ClientSize.Height-$lc.Height)/2)
  foreach($c in $lc.Controls){ if($c.Tag -eq 'center'){ $c.Left=[int](($lc.Width-$c.Width)/2) } } }
$ov.Add_Resize({ Center-Login })
function Set-LoginMode($m){
  $script:lmode=$m; $create=($m -eq 'create')
  foreach($pair in @(@($tabIn,'signin'),@($tabNew,'create'))){
    $b=$pair[0]; $act=($pair[1] -eq $m)
    $b.BackColor=if($act){$pr}else{$bg}; $b.ForeColor=if($act){$white}else{$mu}
    $b.FlatAppearance.MouseOverBackColor=if($act){$prh}else{$hot}
    $script:fadeTo.Remove($b); $script:bcol.Remove($b); $b.Invalidate() }
  $lConf.Visible=$create; $tbPw2.Parent.Visible=$create
  $y=if($create){ 406 }else{ 340 }
  $cbRem.Top=Px $y; $btnLogin.Top=Px ($y+32); $lErr.Top=Px ($y+82); $lGuest.Top=Px ($y+108)
  $lc.Height=Px ($y+146); $btnLogin.Text=if($create){ 'Create account' }else{ 'Sign in' }
  $btnLogin.Invalidate(); $lErr.Text=''; Center-Login }
function Login-Error($m){ $lErr.Text=$m }
function Show-Login{
  $ov.Visible=$true; $ov.BringToFront()
  Set-LoginMode $(if($script:acct.users.Count -eq 0){ 'create' }else{ 'signin' })
  $f.AcceptButton=$btnLogin; $tbUser.Focus() | Out-Null }
function Hide-Login{ $ov.Visible=$false; $f.AcceptButton=$null; $tbPw.Text=''; $tbPw2.Text='' }
function Sign-In($u){
  $script:user=$u; $u.last=Now-Str
  $script:acct.remember=if($cbRem.Checked){ $u.name }else{ '' }
  Save-Accounts; Hide-Login
  if($script:cur -eq 'prof'){ Load-Profiles }
  try{ if($u.cap -ge 0 -and $u.cap -lt $cbCap.Items.Count){ $cbCap.SelectedIndex=[int]$u.cap } }catch{}
  Refresh-Account }
function Do-Login{
  $n=$tbUser.Text.Trim(); $p=$tbPw.Text
  if($script:lockUntil -and (Get-Date) -lt $script:lockUntil){ Login-Error "Too many tries. Wait $([int]($script:lockUntil-(Get-Date)).TotalSeconds) seconds."; return }
  $f.Cursor='WaitCursor'; DE
  try{
    if($script:lmode -eq 'create'){
      if($n -notmatch '^[\p{L}\p{N}_. \-]{3,20}$'){ Login-Error 'Username: 3-20 letters, numbers, spaces or _ . -'; return }
      if($p.Length -lt 6){ Login-Error 'Password needs at least 6 characters.'; return }
      if($p -ne $tbPw2.Text){ Login-Error "The passwords don't match."; return }
      if(Find-User $n){ Login-Error 'That username is already taken.'; return }
      $salt=New-Salt
      $u=[pscustomobject]@{ name=$n; salt=$salt; hash=(Hash-Pw $p $salt); created=(Now-Str); last=(Now-Str); cap=0
        stats=[pscustomobject]@{ boosts=0; pings=0; best=0; cleaned=0; fnApplies=0 }; history=[object[]]@() }
      $script:acct.users=[object[]](@($script:acct.users)+@($u))
      Sign-In $u; Log "Account created. Welcome, $n!" $ac; Start-Wizard }
    else{
      $u=Find-User $n
      if(-not $u -or (Hash-Pw $p $u.salt) -ne $u.hash){
        $script:fails++; if($script:fails -ge 5){ $script:lockUntil=(Get-Date).AddSeconds(30); $script:fails=0 }
        Login-Error 'Wrong username or password.'; return }
      $script:fails=0; Sign-In $u; Log "Welcome back, $($u.name)!" $ac } }
  finally{ $f.Cursor='Default' } }
$script:wizStep=0
$wizSteps=@(
  @{ t='Make a safety backup'; d="Before changing anything, create a restore point so you can undo everything if needed. Takes about a minute."; b='Create restore point'; a={
      Busy 'Creating a restore point...'
      try{ RegSet 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore' SystemRestorePointCreationFrequency 0
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description 'FX Tweaks' -RestorePointType MODIFY_SETTINGS -Confirm:$false -ErrorAction Stop
        Done; Log 'Restore point created.' $ac }
      catch{ Done; Log "Couldn't create a restore point (you can skip this)." $warn } } },
  @{ t='Check your connection'; d="Run a quick ping test to see how fast and stable your internet is to the game servers."; b='Run ping test'; a={ Show-Page 'home'; DE; Run-PingTest; Show-Page 'wiz' } },
  @{ t='Boost your PC'; d="Apply every recommended Windows tweak at once: power plan, game priority, lower latency and more."; b='Boost now'; a={ Quick-Boost } },
  @{ t='Optimize Fortnite'; d="Close Fortnite first. This sets Fortnite to the flat pro look (Performance mode, low detail) for the most FPS."; b='Apply Potato mode'; a={ Show-Page 'fn'; Apply-Potato; Show-Page 'wiz' } } )

$pgWiz=New-Page 'wiz' 'Quick setup' 'A few quick steps to get you ready to play.'
$wizCard=Pnl $pgWiz 28 110 734 300 $pn 16
$wizNum=Lbl '' 28 26 11 $ac $true $wizCard
$wizTitle=Lbl '' 28 54 17 $tx $true $wizCard
$wizDesc=Lbl '' 30 98 10.5 $mu $false $wizCard; $wizDesc.MaximumSize=New-Object Drawing.Size(680,0)
$wizDo=Btn '' 28 210 250 44 { & $wizSteps[$script:wizStep].a; Wizard-Next } 'primary' $wizCard
$wizSkip=Btn 'Skip this step' 290 210 150 44 { Wizard-Next } 'secondary' $wizCard
$wizDots=New-Object Windows.Forms.Panel; $wizDots.Location=New-Object Drawing.Point(28,430); $wizDots.Size=New-Object Drawing.Size(400,16); $wizDots.BackColor=$bg
DoubleBuffer $wizDots; $pgWiz.Controls.Add($wizDots)
$wizDots.Add_Paint({ try{ $g=$_.Graphics; $g.SmoothingMode='AntiAlias'
  for($i=0;$i -lt $wizSteps.Count;$i++){ $col=if($i -eq $script:wizStep){$pr}elseif($i -lt $script:wizStep){$okc}else{$pn}
    $g.FillEllipse((Br $col),(Px ($i*26)),(Px 3),(Px 10),(Px 10)) } }catch{} })
$wizExit=Btn 'Exit setup' 612 430 150 30 { Show-Page 'start0' } 'card' $pgWiz
function Show-WizStep{
  $n=$wizSteps.Count; if($script:wizStep -ge $n){ Finish-Wizard; return }
  $s0=$wizSteps[$script:wizStep]
  $wizNum.Text="STEP $($script:wizStep+1) OF $n"; $wizTitle.Text=$s0.t; $wizDesc.Text=$s0.d; $wizDo.Text=$s0.b
  $wizDo.Width=[math]::Max((Px 150),[Windows.Forms.TextRenderer]::MeasureText($s0.b,$wizDo.Font).Width+(Px 40))
  $wizSkip.Left=$wizDo.Right+(Px 12); $wizDots.Invalidate() }
function Wizard-Next{ $script:wizStep++; if($script:wizStep -ge $wizSteps.Count){ Finish-Wizard }else{ Show-WizStep } }
function Start-Wizard{ $script:wizStep=0; Show-Page 'wiz'; Show-WizStep }
function Finish-Wizard{
  if($script:user){ try{ RegSet 'HKCU\Software\FXTweaks' ("Setup_"+($script:user.name -replace '\W','_')) 1 }catch{} }
  Show-Page 'start0'; Log 'Setup complete. You are ready to play!' $ac }

function Continue-Guest{ $script:user=$null; Hide-Login; Refresh-Account; Log 'Using FX Tweaks as a guest. Stats are not saved.' }
function Sign-Out{
  $script:user=$null; $script:acct.remember=''; Save-Accounts; Refresh-Account; $tbUser.Text=''; Show-Login }
function Delete-Account{
  if(-not $script:user){ return }
  $a=[Windows.Forms.MessageBox]::Show("Delete the account '$($script:user.name)' and all its stats and history?`n`nThis can't be undone. Your PC tweaks stay as they are.",'Delete account','YesNo','Warning')
  if($a -ne 'Yes'){ return }
  $n=$script:user.name; $script:acct.users=[object[]]@($script:acct.users | Where-Object { $_.name -ine $n })
  $script:user=$null; $script:acct.remember=''; Save-Accounts; Refresh-Account; $tbUser.Text=''; Show-Login
  Log "Account '$n' deleted." }

function Change-Password{
  if(-not $script:user){ return }
  $d=New-Object Windows.Forms.Form; $d.Text='Change password'; $d.FormBorderStyle='FixedDialog'; $d.MaximizeBox=$false; $d.MinimizeBox=$false
  $d.StartPosition='CenterParent'; $d.ShowInTaskbar=$false; $d.BackColor=$bg; $d.ForeColor=$tx; $d.Font=$fUI; $d.AutoScaleMode='None'
  $d.ClientSize=New-Object Drawing.Size((Px 360),(Px 300)); $d.Icon=$f.Icon
  $d.Add_HandleCreated({ Dwm $this.Handle 20 1; Dwm $this.Handle 35 (CRef $bg); Dwm $this.Handle 33 2 })
  $script:cp=@{ d=$d }
  [void](Lbl 'Current password' 24 16 9 $mu $false $d); $script:cp.old=Field $d 24 36 312 $true
  [void](Lbl 'New password' 24 84 9 $mu $false $d);     $script:cp.new=Field $d 24 104 312 $true
  [void](Lbl 'Confirm new password' 24 152 9 $mu $false $d); $script:cp.conf=Field $d 24 172 312 $true
  $script:cp.err=Lbl '' 24 216 9 $bad $false $d
  [void](Btn 'Cancel' 24 244 150 40 { $script:cp.d.Close() } 'secondary' $d)
  $save=Btn 'Save' 186 244 150 40 {
    $u=$script:user
    if((Hash-Pw $script:cp.old.Text $u.salt) -ne $u.hash){ $script:cp.err.Text='Current password is wrong.'; return }
    if($script:cp.new.Text.Length -lt 6){ $script:cp.err.Text='New password needs at least 6 characters.'; return }
    if($script:cp.new.Text -ne $script:cp.conf.Text){ $script:cp.err.Text="The new passwords don't match."; return }
    $u.salt=New-Salt; $u.hash=Hash-Pw $script:cp.new.Text $u.salt; Save-Accounts
    Log 'Password changed.' $ac; $script:cp.d.Close() } 'primary' $d
  $d.AcceptButton=$save
  if($S -gt 1.01){ foreach($c in @($d.Controls)){ $c.Scale((New-Object Drawing.SizeF([single]$S,[single]$S))) } }
  [void]$d.ShowDialog($f); $d.Dispose() }

# =========================================================
#  PROFILES (snapshots of every setting you can go back to)
# =========================================================
Step 'Building Profiles...'
$pgProf=New-Page 'prof' 'Profiles' 'Save your settings and go back anytime. A backup is also saved before every change.'
$tbProfHost=Pnl $pgProf 28 92 300 36 $pn 10
$tbProf=New-Object Windows.Forms.TextBox; $tbProf.BorderStyle='None'; $tbProf.Location=New-Object Drawing.Point(12,9); $tbProf.Width=276
$tbProf.BackColor=$pn; $tbProf.ForeColor=$tx; $tbProf.Font=$fUI; $tbProfHost.Controls.Add($tbProf); $tbProfHost.Add_Click({ $tbProf.Focus() })
[void](Btn 'Save current' 338 92 140 36 {
  $n=$tbProf.Text.Trim(); if(-not $n){ $n="My settings $(Get-Date -Format 'dd.MM HH:mm')" }
  Save-Snapshot $n $false; $tbProf.Text=''; Log "Saved profile '$n'." $ac; Add-History 'Profile saved' $n } 'secondary' $pgProf)
$prRestore=Btn 'Go back to this' 502 92 150 36 { $p=Sel-Profile; if($p){ Restore-Profile $p } } 'primary' $pgProf
[void](Btn 'Delete' 662 92 100 36 {
  $p=Sel-Profile; if(-not $p){ return }
  if([Windows.Forms.MessageBox]::Show("Delete the profile '$($p.name)'?",'Profiles','YesNo','Question') -eq 'Yes'){
    Remove-Item -LiteralPath $p.file -Force -ErrorAction SilentlyContinue; Log "Deleted profile '$($p.name)'."; Load-Profiles } } 'secondary' $pgProf)
$lvProf=New-List $pgProf 28 140 734 470 @(@('Profile',280),@('Saved',150),@('Type',110),@('Contains',0)) $false
$lvProf.MultiSelect=$false
$lvProf.Add_MouseDoubleClick({ $p=Sel-Profile; if($p){ Restore-Profile $p } })

function Prof-Dir{
  $o=if($script:user){ $script:user.name -replace '[\\/:*?"<>|]','_' }else{ '_guest' }
  Join-Path $ACCT_DIR "profiles\$o" }
function Get-Profiles{
  $dir=Prof-Dir; if(-not (Test-Path $dir)){ return }
  $all=foreach($fl in Get-ChildItem -LiteralPath $dir -Filter *.json -ErrorAction SilentlyContinue){
    try{ $o=[IO.File]::ReadAllText($fl.FullName) | ConvertFrom-Json; $o | Add-Member -NotePropertyName file -NotePropertyValue $fl.FullName -Force; $o }catch{} }
  $all | Sort-Object { [long]$_.ticks } -Descending }
function Load-Profiles{
  $lvProf.BeginUpdate(); $lvProf.Items.Clear()
  $list=@(Get-Profiles)
  foreach($p in $list){
    $cnt=@($p.tweaks.PSObject.Properties).Count
    $what="$cnt Windows settings" + $(if($p.fnIni){ ' + Fortnite' }else{ '' })
    $it=Add-Row $lvProf @($p.name,$p.date,$(if($p.auto){ 'Automatic' }else{ 'Saved by you' }),$what) $p
    Set-CellColor $it 1 $mu; Set-CellColor $it 2 $(if($p.auto){ $mu }else{ $ac }); Set-CellColor $it 3 $mu }
  if($list.Count -eq 0){ [void](Add-Row $lvProf @('No profiles yet: type a name and click Save current','','','') $null $mu) }
  $lvProf.EndUpdate() }
function Sel-Profile{
  $it=$lvProf.SelectedItems | Select-Object -First 1
  if(-not $it -or $null -eq $it.Tag.Data){ Log 'Click a profile in the list first.' $warn; return $null }
  $it.Tag.Data }

function Save-Snapshot($name,$auto){
  Busy 'Saving a backup of your settings...'
  try{
    $tw=[ordered]@{}; foreach($t in $tweaks){ $tw[$t.Name]=(Test-Tweak $t); DE }
    $ini=$null; $uni=$false; $locked=$false
    if(Test-Path $FNINI){ try{
      $b=[IO.File]::ReadAllBytes($FNINI); $uni=($b.Length -ge 2 -and $b[0] -eq 0xFF -and $b[1] -eq 0xFE)
      $ini=[IO.File]::ReadAllText($FNINI); $locked=(Get-Item $FNINI).IsReadOnly }catch{} }
    $p=[pscustomobject]@{ name=$name; date=(Now-Str); ticks=(Get-Date).Ticks; auto=[bool]$auto; tweaks=[pscustomobject]$tw
      fnIni=$ini; iniUnicode=$uni; locked=$locked; cap=$cbCap.SelectedIndex; res=$cbRes.SelectedIndex }
    $dir=Prof-Dir; New-Item -ItemType Directory $dir -Force | Out-Null
    $file=Join-Path $dir ("{0}.json" -f [guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText($file,(ConvertTo-Json -InputObject $p -Depth 4),(New-Object Text.UTF8Encoding($false)))
    if($auto){ @(Get-Profiles | Where-Object { $_.auto }) | Select-Object -Skip 8 | ForEach-Object { Remove-Item -LiteralPath $_.file -Force -ErrorAction SilentlyContinue } } }
  catch{ Log "Couldn't save a backup: $($_.Exception.Message)" $bad }
  Done; if($script:cur -eq 'prof'){ Load-Profiles } }

function Restore-Profile($p){
  $a=[Windows.Forms.MessageBox]::Show("Go back to '$($p.name)' from $($p.date)?`n`nYour current settings are saved first, so you can undo this.",'Profiles','YesNo','Question')
  if($a -ne 'Yes'){ return }
  Save-Snapshot "Before going back to '$($p.name)'" $true
  Busy "Restoring '$($p.name)'..."; $n=0
  foreach($t in $tweaks){
    $want=$p.tweaks.($t.Name); if($null -eq $want){ continue }
    if([bool]$want -ne (Test-Tweak $t)){
      $st.Text="Restoring: $($t.Name)"; DE
      try{ if($want){ & $t.On }else{ & $t.Off }; $n++ }catch{ Log "Couldn't change: $($t.Name)" $warn } } }
  if($p.fnIni){
    if(Get-Process -Name $FN -ErrorAction SilentlyContinue){ Log 'Fortnite is running, so its settings were skipped. Close it and go back again.' $warn }
    else{ try{
      New-Item -ItemType Directory (Split-Path $FNINI) -Force | Out-Null
      if(Test-Path $FNINI){ (Get-Item $FNINI).IsReadOnly=$false }
      $enc=if($p.iniUnicode){ [Text.Encoding]::Unicode }else{ New-Object Text.UTF8Encoding($false) }
      [IO.File]::WriteAllText($FNINI,$p.fnIni,$enc)
      if($p.locked){ (Get-Item $FNINI).IsReadOnly=$true }
      $n++ }catch{ Log "Couldn't restore Fortnite settings: $($_.Exception.Message)" $bad } } }
  try{ if($p.cap -ge 0 -and $p.cap -lt $cbCap.Items.Count){ $cbCap.SelectedIndex=[int]$p.cap }
       if($p.res -ge 0 -and $p.res -lt $cbRes.Items.Count){ $cbRes.SelectedIndex=[int]$p.res } }catch{}
  Done; Refresh-Opt; Refresh-State; if($loaded['fn']){ Load-FnSettings }
  Log "Went back to '$($p.name)' ($n changes). Restart your PC if Windows settings changed." $ac
  Add-History 'Went back to profile' $p.name
  Load-Profiles }
$loaders['prof']={ Load-Profiles }

# =========================================================
#  Navigation + shortcut
# =========================================================
Step 'Building the menu...'
NavItem 'start0' 0xE80F 'Start'
NavItem 'home'   0xE10F 'Connection'
NavItem 'fn'     0xE7FC 'Fortnite'
NavItem 'opt'    0xE945 'Optimize'
NavItem 'prof'   0xE81C 'Profiles'
NavItem 'apps'   0xE9D9 'Running apps'
NavItem 'start'  0xE7E8 'Startup apps'
NavItem 'clean'  0xE74D 'Clean up files'
NavItem 'remove' 0xE71D 'Remove apps'
NavItem 'acct'   0xE77B 'Account'
$navBar.BringToFront()

function New-Shortcut{
  try{
    if(-not $bat){ throw 'the app path is unknown' }
    $dir=Join-Path $env:LOCALAPPDATA 'FX Tweaks'; New-Item -ItemType Directory $dir -Force | Out-Null
    $ico=Join-Path $dir 'fx.ico'; Save-FXIco $ico
    $ws=New-Object -ComObject WScript.Shell
    foreach($d in @([Environment]::GetFolderPath('Desktop'),[Environment]::GetFolderPath('Programs'))){
      $l=$ws.CreateShortcut((Join-Path $d 'FX Tweaks.lnk'))
      $l.TargetPath=$bat; $l.WorkingDirectory=Split-Path $bat; $l.IconLocation="$ico,0"; $l.WindowStyle=7; $l.Description='FX Tweaks'; $l.Save() }
    Log 'FX shortcut added to your desktop and Start menu.' $ac }
  catch{ Log "Couldn't create the shortcut: $($_.Exception.Message)" $bad } }
$fnLbl=Lbl 'Fortnite: checking...' 18 574 9 $mu $false $side
$shortcutBtn=Btn 'Add desktop shortcut' 12 600 186 34 { New-Shortcut } 'secondary' $side

$fnTimer=New-Object Windows.Forms.Timer; $fnTimer.Interval=3000
$fnTimer.Add_Tick({ try{
  $p=Get-Process -Name $FN -ErrorAction SilentlyContinue | Select-Object -First 1
  if($p){ if($p.Id -ne $script:fnPid){ $script:fnPid=$p.Id; $script:fnStart=Get-FnState; Optimize-Fortnite $p } }
  elseif($script:fnPid){ $script:fnPid=0; Resume-Updates; Start-Sleep -Milliseconds 1500; Check-FnKept; Set-FnStatus 'Fortnite: not running (watching)' $mu } }catch{} })
$script:fnPid=0

Step 'Scaling for your screen...'
# ---- scale everything to the screen's DPI so text is sharp ----
$f.AutoScaleMode='None'; $f.MinimumSize=New-Object Drawing.Size(0,0)
if($S -gt 1.01){
  $sf=New-Object Drawing.SizeF([single]$S,[single]$S)
  foreach($c in @($f.Controls)){ $c.Scale($sf) }
  $f.ClientSize=New-Object Drawing.Size((Px 1000),(Px 660)) }
$f.MinimumSize=$f.Size

# ---- anchors so the window can be resized / maximized ----
$side.Anchor='Top,Bottom,Left'; $stBar.Anchor='Bottom,Left,Right'
foreach($c in $stBar.Controls){ if($c -is [Windows.Forms.Panel]){ $c.Anchor='Top,Left,Right' } }
foreach($pg in $pages.Values){ $pg.Anchor='Top,Bottom,Left,Right'
  foreach($c in $pg.Controls){
    if($c.Tag -eq 'listhost'){ $c.Anchor='Top,Bottom,Left,Right' }
    elseif($c.Right -ge (Px 700)){ $c.Anchor='Top,Right' } } }
$card.Anchor='Top,Left,Right'; foreach($c in $card.Controls){ if($c.Left -ge (Px 280)){ $c.Anchor='Top,Right' } }
$lvPing.Parent.Anchor='Top,Left,Right'; $logHost.Anchor='Top,Bottom,Left,Right'; $log.Anchor='Top,Bottom,Left,Right'
$tbHost.Anchor='Top,Left,Right'; $tb.Anchor='Top,Left,Right'
$memLbl.Anchor='Top,Right'; $junkTotal.Anchor='Top,Right'
$wizCard.Anchor='Top,Left,Right'; $wizExit.Anchor='Top,Right'
$prRestore.Anchor='Top,Right'; foreach($sm in $optSum,$fnSum){ $sm.Label.Anchor='Top,Right'; $sm.Bar.Anchor='Top,Right' } $acCard.Anchor='Top,Left,Right'; $acDel.Anchor='Bottom,Right'
$lvFn.Parent.Anchor='Top,Left,Right'; $capLbl.Anchor='Top,Right'; $vivBtn.Anchor='Top,Right'; $resLbl.Anchor='Top,Right'; $resHost.Anchor='Top,Right'; $chkBtn.Anchor='Top,Right'
$shortcutBtn.Anchor='Bottom,Left'; $fnLbl.Anchor='Bottom,Left'
$f.Add_Resize({ try{ if($script:cur){ $pages[$script:cur].Size=New-Object Drawing.Size(($f.ClientSize.Width-$side.Width),($f.ClientSize.Height-$stBar.Height)) } }catch{} })

# =========================================================
#  Window polish: dark title bar, dark scrollbars, fade-in
# =========================================================
$f.Add_HandleCreated({
  $h=$f.Handle; Dwm $h 20 1; Dwm $h 19 1; Dwm $h 33 2; Dwm $h 35 (CRef $bg); Dwm $h 36 (CRef $tx); Dwm $h 34 (CRef $bd) })
$f.Add_Load({
  $f.Opacity=0.01
  foreach($c in $script:themed){ try{ [void][FXNative]::SetWindowTheme($c.Handle,'DarkMode_Explorer',[NullString]::Value) }catch{} }
  try{ [void][FXNative]::SendMessage($tb.Handle,0x1501,[IntPtr]1,'Server IP (optional)'); [void][FXNative]::SendMessage($tbProf.Handle,0x1501,[IntPtr]1,'Profile name, e.g. Tournament') }catch{} })
$f.Add_FormClosing({ try{ Resume-Updates }catch{} })
$f.Add_Shown({
  try{ $f.TopMost=$true; $f.Activate(); $f.TopMost=$false }catch{}
  $startTimer.Start()
  try{ for($i=1;$i -le 12;$i++){ $f.Opacity=$i/12; $f.Update(); Start-Sleep -Milliseconds 12 } }
  finally{ $f.Opacity=1 } })

Show-Page 'start0'
$fnTweak=$tweaks | Where-Object { $_.Name -like 'Fortnite*' } | Select-Object -First 1
$boost.Text='checking...'; $boost.BackColor=$hv; $boost.ForeColor=$mu
function Finish-Startup{
  try{
    if(-not (Test-Tweak $fnTweak)){ try{ & $fnTweak.On; Log 'Fortnite tweaks applied automatically.' $ac }catch{} }
    if($script:fnExe){ Set-FnStatus 'Fortnite: ready (watching)' $ac }else{ Set-FnStatus 'Fortnite: not found (watching)' $mu }
    if($script:vivCrashed){ Log 'Vivid colors crashed the app last time, so it has been turned off. Use NVIDIA Control Panel > Digital Vibrance instead.' $warn }
    if($script:fnOtherUser){ Log "Using the Fortnite settings of the signed-in Windows user: $FNINI" }
    Refresh-State }
  catch{ Log "Startup check failed: $($_.Exception.Message)" $warn }
  $fnTimer.Start() }
$startTimer=New-Object Windows.Forms.Timer; $startTimer.Interval=400
$startTimer.Add_Tick({ $startTimer.Stop(); Finish-Startup })
Step 'Opening...'
$ov.BringToFront()
$rem=if($script:acct.remember){ Find-User $script:acct.remember }else{ $null }
if($rem){ $script:user=$rem; $rem.last=Now-Str; Save-Accounts; $ov.Visible=$false
  try{ if($rem.cap -ge 0 -and $rem.cap -lt $cbCap.Items.Count){ $cbCap.SelectedIndex=[int]$rem.cap } }catch{}
  Refresh-Account }
else{ Refresh-Account; Show-Login }
Log $(if($script:user){ "Welcome back, $($script:user.name). FX Tweaks optimizes Fortnite automatically." }else{ 'Welcome. FX Tweaks optimizes Fortnite automatically whenever it starts.' })
try{ $splash.Close(); $splash.Dispose() }catch{}
$f.Owner=$null
[void]$f.ShowDialog()
}catch{
  try{ $splash.Close() }catch{}
  $msg="$($_.Exception.Message)`n`nLine $($_.InvocationInfo.ScriptLineNumber): $($_.InvocationInfo.Line.Trim())"
  try{ $msg | Out-File (Join-Path $env:TEMP 'FXTweaks_error.txt') }catch{}
  [void][Windows.Forms.MessageBox]::Show("FX Tweaks couldn't start.`n`n$msg`n`n(Saved to %TEMP%\FXTweaks_error.txt. Startup steps: %TEMP%\FXTweaks_startup.txt)",'FX Tweaks','OK','Error')
}
