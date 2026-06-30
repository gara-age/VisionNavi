param(
  [string]$Title = "VisionNavi",
  [string]$Message = "알림",
  [int]$DurationMs = 5000,
  [string]$State = "info",
  [string]$ThemeMode = "light",
  [string]$LargeText = "0"
)

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class PopupWindowInterop {
  public const int GWL_EXSTYLE = -20;
  public const int WS_EX_TOOLWINDOW = 0x00000080;
  public const int WS_EX_NOACTIVATE = 0x08000000;

  [DllImport("user32.dll")]
  public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

  [DllImport("user32.dll")]
  public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
}
"@

function Get-ScriptAssetPath {
  param([string]$RelativePath)
  return Join-Path $PSScriptRoot $RelativePath
}

function Get-PretendardFontFamily {
  $fontCandidates = @(
    (Join-Path $PSScriptRoot '..\frontend\build\windows\x64\runner\Release\data\flutter_assets\assets\fonts'),
    (Join-Path $PSScriptRoot '..\frontend\build\windows\x64\runner\Debug\data\flutter_assets\assets\fonts'),
    (Join-Path $PSScriptRoot '..\data\flutter_assets\assets\fonts'),
    (Join-Path $PSScriptRoot '..\..\data\flutter_assets\assets\fonts'),
    (Join-Path $PSScriptRoot '..\frontend\assets\fonts'),
    (Join-Path (Get-Location) 'assets\fonts')
  )

  foreach ($fontDir in $fontCandidates) {
    if (-not (Test-Path $fontDir)) {
      continue
    }

    try {
      $resolved = (Resolve-Path $fontDir).Path -replace '\\', '/'
      return New-Object System.Windows.Media.FontFamily("file:///$resolved/#Pretendard")
    } catch {
      continue
    }
  }

  return New-Object System.Windows.Media.FontFamily('Segoe UI')
}

function Convert-ToMediaColor {
  param([string]$Hex)

  if ([string]::IsNullOrWhiteSpace($Hex) -or -not $Hex.StartsWith('#')) {
    return [System.Windows.Media.Color]::FromArgb(0, 0, 0, 0)
  }

  $value = $Hex.Substring(1)
  if ($value.Length -eq 6) {
    return [System.Windows.Media.Color]::FromArgb(
      255,
      [Convert]::ToByte($value.Substring(0, 2), 16),
      [Convert]::ToByte($value.Substring(2, 2), 16),
      [Convert]::ToByte($value.Substring(4, 2), 16)
    )
  }

  if ($value.Length -eq 8) {
    return [System.Windows.Media.Color]::FromArgb(
      [Convert]::ToByte($value.Substring(0, 2), 16),
      [Convert]::ToByte($value.Substring(2, 2), 16),
      [Convert]::ToByte($value.Substring(4, 2), 16),
      [Convert]::ToByte($value.Substring(6, 2), 16)
    )
  }

  return [System.Windows.Media.Color]::FromArgb(0, 0, 0, 0)
}

function New-Brush {
  param([string]$Hex)
  return New-Object System.Windows.Media.SolidColorBrush((Convert-ToMediaColor -Hex $Hex))
}

function Convert-StrokeCap {
  param([string]$Value)
  switch ($Value) {
    'round' { return [System.Windows.Media.PenLineCap]::Round }
    'square' { return [System.Windows.Media.PenLineCap]::Square }
    default { return [System.Windows.Media.PenLineCap]::Flat }
  }
}

function Convert-StrokeJoin {
  param([string]$Value)
  switch ($Value) {
    'round' { return [System.Windows.Media.PenLineJoin]::Round }
    'bevel' { return [System.Windows.Media.PenLineJoin]::Bevel }
    default { return [System.Windows.Media.PenLineJoin]::Miter }
  }
}

function New-SvgViewbox {
  param(
    [string]$SvgPath,
    [string]$StrokeHex
  )

  $svg = [xml](Get-Content -Path $SvgPath -Raw)
  $parts = ($svg.svg.viewBox -split '\s+')
  $canvas = New-Object System.Windows.Controls.Canvas
  $canvas.Width = [double]$parts[2]
  $canvas.Height = [double]$parts[3]

  foreach ($node in $svg.svg.ChildNodes) {
    if ($node.NodeType -ne [System.Xml.XmlNodeType]::Element) {
      continue
    }

    $strokeBrush = New-Brush -Hex $StrokeHex
    $strokeWidth = if ($node.'stroke-width') { [double]$node.'stroke-width' } else { 2.0 }
    $lineCap = Convert-StrokeCap -Value $node.'stroke-linecap'
    $lineJoin = Convert-StrokeJoin -Value $node.'stroke-linejoin'

    switch ($node.Name) {
      'path' {
        $shape = New-Object System.Windows.Shapes.Path
        $shape.Data = [System.Windows.Media.Geometry]::Parse($node.d)
        $shape.Stroke = $strokeBrush
        $shape.StrokeThickness = $strokeWidth
        $shape.StrokeStartLineCap = $lineCap
        $shape.StrokeEndLineCap = $lineCap
        $shape.StrokeLineJoin = $lineJoin
        $shape.Fill = [System.Windows.Media.Brushes]::Transparent
        [void]$canvas.Children.Add($shape)
      }
      'rect' {
        $shape = New-Object System.Windows.Shapes.Rectangle
        $shape.Width = [double]$node.width
        $shape.Height = [double]$node.height
        $shape.RadiusX = if ($node.rx) { [double]$node.rx } else { 0 }
        $shape.RadiusY = if ($node.ry) { [double]$node.ry } else { $shape.RadiusX }
        $shape.Stroke = $strokeBrush
        $shape.StrokeThickness = $strokeWidth
        $shape.Fill = [System.Windows.Media.Brushes]::Transparent
        [System.Windows.Controls.Canvas]::SetLeft($shape, [double]$node.x)
        [System.Windows.Controls.Canvas]::SetTop($shape, [double]$node.y)
        [void]$canvas.Children.Add($shape)
      }
      'circle' {
        $shape = New-Object System.Windows.Shapes.Ellipse
        $r = [double]$node.r
        $shape.Width = $r * 2
        $shape.Height = $r * 2
        $shape.Stroke = $strokeBrush
        $shape.StrokeThickness = $strokeWidth
        $shape.Fill = [System.Windows.Media.Brushes]::Transparent
        [System.Windows.Controls.Canvas]::SetLeft($shape, ([double]$node.cx - $r))
        [System.Windows.Controls.Canvas]::SetTop($shape, ([double]$node.cy - $r))
        [void]$canvas.Children.Add($shape)
      }
      'line' {
        $shape = New-Object System.Windows.Shapes.Line
        $shape.X1 = [double]$node.x1
        $shape.Y1 = [double]$node.y1
        $shape.X2 = [double]$node.x2
        $shape.Y2 = [double]$node.y2
        $shape.Stroke = $strokeBrush
        $shape.StrokeThickness = $strokeWidth
        $shape.StrokeStartLineCap = $lineCap
        $shape.StrokeEndLineCap = $lineCap
        [void]$canvas.Children.Add($shape)
      }
    }
  }

  $viewbox = New-Object System.Windows.Controls.Viewbox
  $viewbox.Stretch = [System.Windows.Media.Stretch]::Uniform
  $viewbox.Child = $canvas
  return $viewbox
}

function Get-IconPath {
  param([string]$PopupState)

  $name = switch ($PopupState.ToLowerInvariant()) {
    'processing' { 'hourglass.svg' }
    'success' { 'check.svg' }
    'warning' { 'warning.svg' }
    'error' { 'error.svg' }
    default { 'info.svg' }
  }

  return Get-ScriptAssetPath "popup_icons\$name"
}

function Build-ThemePalette {
  param(
    [string]$PopupState,
    [string]$PopupTheme
  )

  $state = $PopupState.ToLowerInvariant()
  $theme = $PopupTheme.ToLowerInvariant()

  if ($theme -eq 'contrast') {
    switch ($state) {
      'processing' { return @{ Bg='#FEF9C3'; Border='#713F12'; IconBg='#FFFFFF'; IconBorder='#713F12'; Icon='#713F12'; Title='#713F12'; Message='#713F12'; CloseBg='#FFFFFF'; CloseBorder='#713F12'; Close='#713F12'; BorderWidth='2'; IconBorderWidth='2'; CloseBorderWidth='2'; TitleWeight='Bold'; MessageWeight='Bold' } }
      'success' { return @{ Bg='#DCFCE7'; Border='#14532D'; IconBg='#FFFFFF'; IconBorder='#14532D'; Icon='#14532D'; Title='#14532D'; Message='#14532D'; CloseBg='#FFFFFF'; CloseBorder='#14532D'; Close='#14532D'; BorderWidth='2'; IconBorderWidth='2'; CloseBorderWidth='2'; TitleWeight='Bold'; MessageWeight='Bold' } }
      'warning' { return @{ Bg='#FFEDD5'; Border='#7C2D12'; IconBg='#FFFFFF'; IconBorder='#7C2D12'; Icon='#7C2D12'; Title='#7C2D12'; Message='#7C2D12'; CloseBg='#FFFFFF'; CloseBorder='#7C2D12'; Close='#7C2D12'; BorderWidth='2'; IconBorderWidth='2'; CloseBorderWidth='2'; TitleWeight='Bold'; MessageWeight='Bold' } }
      'error' { return @{ Bg='#FEE2E2'; Border='#7F1D1D'; IconBg='#FFFFFF'; IconBorder='#7F1D1D'; Icon='#7F1D1D'; Title='#7F1D1D'; Message='#7F1D1D'; CloseBg='#FFFFFF'; CloseBorder='#7F1D1D'; Close='#7F1D1D'; BorderWidth='2'; IconBorderWidth='2'; CloseBorderWidth='2'; TitleWeight='Bold'; MessageWeight='Bold' } }
      default { return @{ Bg='#DBEAFE'; Border='#1E3A8A'; IconBg='#FFFFFF'; IconBorder='#1E3A8A'; Icon='#1E3A8A'; Title='#020617'; Message='#1E3A8A'; CloseBg='#FFFFFF'; CloseBorder='#1E3A8A'; Close='#111827'; BorderWidth='2'; IconBorderWidth='2'; CloseBorderWidth='2'; TitleWeight='Bold'; MessageWeight='Bold' } }
    }
  }

  if ($theme -eq 'dark') {
    switch ($state) {
      'processing' { return @{ Bg='#1F2937'; Border='#F59E0B'; IconBg='#78350F'; IconBorder='#FDE68A'; Icon='#FDE68A'; Title='#FFFFFF'; Message='#E5E7EB'; CloseBg='#1F2937'; CloseBorder='#FCD34D'; Close='#FCD34D'; BorderWidth='1.5'; IconBorderWidth='1'; CloseBorderWidth='1'; TitleWeight='Bold'; MessageWeight='Medium' } }
      'success' { return @{ Bg='#14532D'; Border='#22C55E'; IconBg='#166534'; IconBorder='#DCFCE7'; Icon='#DCFCE7'; Title='#FFFFFF'; Message='#D1FAE5'; CloseBg='#14532D'; CloseBorder='#BBF7D0'; Close='#BBF7D0'; BorderWidth='1.5'; IconBorderWidth='1'; CloseBorderWidth='1'; TitleWeight='Bold'; MessageWeight='Medium' } }
      'warning' { return @{ Bg='#7C2D12'; Border='#FB923C'; IconBg='#9A3412'; IconBorder='#FFEDD5'; Icon='#FFEDD5'; Title='#FFFFFF'; Message='#FED7AA'; CloseBg='#7C2D12'; CloseBorder='#FED7AA'; Close='#FED7AA'; BorderWidth='1.5'; IconBorderWidth='1'; CloseBorderWidth='1'; TitleWeight='Bold'; MessageWeight='Medium' } }
      'error' { return @{ Bg='#7F1D1D'; Border='#EF4444'; IconBg='#991B1B'; IconBorder='#FEE2E2'; Icon='#FEE2E2'; Title='#FFFFFF'; Message='#FECACA'; CloseBg='#7F1D1D'; CloseBorder='#FCA5A5'; Close='#FCA5A5'; BorderWidth='1.5'; IconBorderWidth='1'; CloseBorderWidth='1'; TitleWeight='Bold'; MessageWeight='Medium' } }
      default { return @{ Bg='#0F172A'; Border='#334155'; IconBg='#1E3A8A'; IconBorder='#BFDBFE'; Icon='#BFDBFE'; Title='#FFFFFF'; Message='#CBD5E1'; CloseBg='#111827'; CloseBorder='#E2E8F0'; Close='#E2E8F0'; BorderWidth='1.5'; IconBorderWidth='1'; CloseBorderWidth='1'; TitleWeight='Bold'; MessageWeight='Medium' } }
    }
  }

  switch ($state) {
    'processing' { return @{ Bg='#FFFFFF'; Border='#FDE68A'; IconBg='#FEF3C7'; IconBorder='#00000000'; Icon='#F59E0B'; Title='#0F172A'; Message='#475569'; CloseBg='#00FFFFFF'; CloseBorder='#00FFFFFF'; Close='#94A3B8'; BorderWidth='1'; IconBorderWidth='0'; CloseBorderWidth='0'; TitleWeight='Bold'; MessageWeight='Medium' } }
    'success' { return @{ Bg='#FFFFFF'; Border='#BBF7D0'; IconBg='#DCFCE7'; IconBorder='#00000000'; Icon='#16A34A'; Title='#0F172A'; Message='#475569'; CloseBg='#00FFFFFF'; CloseBorder='#00FFFFFF'; Close='#94A3B8'; BorderWidth='1'; IconBorderWidth='0'; CloseBorderWidth='0'; TitleWeight='Bold'; MessageWeight='Medium' } }
    'warning' { return @{ Bg='#FFFFFF'; Border='#FDE68A'; IconBg='#FFF7ED'; IconBorder='#00000000'; Icon='#EA580C'; Title='#0F172A'; Message='#475569'; CloseBg='#00FFFFFF'; CloseBorder='#00FFFFFF'; Close='#94A3B8'; BorderWidth='1'; IconBorderWidth='0'; CloseBorderWidth='0'; TitleWeight='Bold'; MessageWeight='Medium' } }
    'error' { return @{ Bg='#FFFFFF'; Border='#FECACA'; IconBg='#FEE2E2'; IconBorder='#00000000'; Icon='#DC2626'; Title='#0F172A'; Message='#475569'; CloseBg='#00FFFFFF'; CloseBorder='#00FFFFFF'; Close='#94A3B8'; BorderWidth='1'; IconBorderWidth='0'; CloseBorderWidth='0'; TitleWeight='Bold'; MessageWeight='Medium' } }
    default { return @{ Bg='#FFFFFF'; Border='#E2E8F0'; IconBg='#EFF6FF'; IconBorder='#00000000'; Icon='#2563EB'; Title='#0F172A'; Message='#475569'; CloseBg='#00FFFFFF'; CloseBorder='#00FFFFFF'; Close='#94A3B8'; BorderWidth='1'; IconBorderWidth='0'; CloseBorderWidth='0'; TitleWeight='Bold'; MessageWeight='Medium' } }
  }
}

function Truncate-Message {
  param(
    [string]$Text,
    [int]$MaxChars
  )

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return ''
  }

  $single = ($Text -replace '\s+', ' ').Trim()
  if ($single.Length -le $MaxChars) {
    return $single
  }

  return ($single.Substring(0, $MaxChars - 3) + '...')
}

$isLargeText = $LargeText -match '^(1|true|yes)$'
$normalizedState = $State.ToLowerInvariant()
$normalizedTheme = $ThemeMode.ToLowerInvariant()
$palette = Build-ThemePalette -PopupState $normalizedState -PopupTheme $normalizedTheme

$popupWidth = if ($isLargeText) { 372 } else { 320 }
$popupHeight = if ($isLargeText) { 118 } else { 96 }
$titleFontSize = if ($isLargeText) { 17 } else { 14 }
$messageFontSize = if ($isLargeText) { 15 } else { 13 }
$safeDuration = [Math]::Max($DurationMs, 1500)
$displayMessage = Truncate-Message -Text $Message -MaxChars $(if ($isLargeText) { 100 } else { 78 })

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="$popupWidth"
        Height="$popupHeight"
        AllowsTransparency="True"
        Background="Transparent"
        WindowStyle="None"
        ResizeMode="NoResize"
        UseLayoutRounding="True"
        SnapsToDevicePixels="True"
        ShowInTaskbar="False"
        ShowActivated="False"
        Topmost="True">
  <Grid>
    <Border Background="$($palette.Bg)"
            BorderBrush="$($palette.Border)"
            BorderThickness="$($palette.BorderWidth)"
            CornerRadius="18"
            Padding="$(if ($isLargeText) { '16,10,16,10' } else { '16,8,16,8' })">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="40"/>
          <ColumnDefinition Width="12"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <Border x:Name="IconBadge"
                Grid.Row="0"
                Grid.RowSpan="2"
                Width="40"
                Height="40"
                Background="$($palette.IconBg)"
                BorderBrush="$($palette.IconBorder)"
                BorderThickness="$($palette.IconBorderWidth)"
                CornerRadius="12"
                HorizontalAlignment="Left"
                VerticalAlignment="Top"/>

        <Grid Grid.Column="2"
              Grid.Row="0"
              Grid.RowSpan="2"
              Margin="0,0,24,0">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <TextBlock x:Name="TitleText"
                     Grid.Row="0"
                     FontFamily="Segoe UI"
                     FontWeight="$($palette.TitleWeight)"
                     FontSize="$titleFontSize"
                     Foreground="$($palette.Title)"
                     TextWrapping="NoWrap"
                     TextTrimming="CharacterEllipsis"/>
          <TextBlock x:Name="MessageText"
                     Grid.Row="1"
                     Margin="0,4,0,0"
                     FontFamily="Segoe UI"
                     FontWeight="$($palette.MessageWeight)"
                     FontSize="$messageFontSize"
                     Foreground="$($palette.Message)"
                     TextWrapping="Wrap"
                     MaxWidth="$(if ($isLargeText) { 248 } else { 220 })"
                     MaxHeight="$(if ($isLargeText) { 72 } else { 56 })"/>
        </Grid>

        <Border x:Name="CloseBadge"
                Grid.Column="2"
                Grid.Row="0"
                Width="24"
                Height="24"
                Background="$($palette.CloseBg)"
                BorderBrush="$($palette.CloseBorder)"
                BorderThickness="$($palette.CloseBorderWidth)"
                CornerRadius="12"
                HorizontalAlignment="Right"
                VerticalAlignment="Top"
                Cursor="Hand"/>
      </Grid>
    </Border>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
$iconBadge = $window.FindName('IconBadge')
$titleText = $window.FindName('TitleText')
$messageText = $window.FindName('MessageText')
$closeBadge = $window.FindName('CloseBadge')
$pretendardFont = Get-PretendardFontFamily

$window.FontFamily = $pretendardFont
$window.ShowActivated = $false
$titleText.Text = $Title
$messageText.Text = $displayMessage
$titleText.FontFamily = $pretendardFont
$messageText.FontFamily = $pretendardFont

$iconSvg = Get-IconPath -PopupState $normalizedState
if (Test-Path $iconSvg) {
  $iconBadge.Child = New-SvgViewbox -SvgPath $iconSvg -StrokeHex $palette.Icon
}

$closeSvg = Get-ScriptAssetPath 'popup_icons\x.svg'
if (Test-Path $closeSvg) {
  $closeBadge.Child = New-SvgViewbox -SvgPath $closeSvg -StrokeHex $palette.Close
}

if ($closeBadge.Child) {
  $closeBadge.Child.Margin = '5'
}

$closeAction = {
  if ($window.IsVisible) {
    $window.Close()
  }
}

$window.Add_SourceInitialized({
  $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
  $extendedStyle = [PopupWindowInterop]::GetWindowLong($helper.Handle, [PopupWindowInterop]::GWL_EXSTYLE)
  $extendedStyle = $extendedStyle -bor [PopupWindowInterop]::WS_EX_TOOLWINDOW -bor [PopupWindowInterop]::WS_EX_NOACTIVATE
  [PopupWindowInterop]::SetWindowLong($helper.Handle, [PopupWindowInterop]::GWL_EXSTYLE, $extendedStyle) | Out-Null

  $screen = [System.Windows.SystemParameters]::WorkArea
  $window.Left = $screen.Right - $popupWidth - 24
  $window.Top = $screen.Bottom - $popupHeight - 24
})

$closeBadge.Add_MouseLeftButtonUp({
  & $closeAction
})

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds($safeDuration)
$timer.Add_Tick({
  $timer.Stop()
  & $closeAction
})

$window.Add_ContentRendered({
  $timer.Start()
})

$window.Add_Closed({
  $timer.Stop()
})

$window.Show()

while ($window.IsVisible) {
  [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
    [Action] {},
    [System.Windows.Threading.DispatcherPriority]::Background
  )
  Start-Sleep -Milliseconds 20
}
