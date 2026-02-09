# Microshlop never learned but at least they provided this option to fix this but whyyyyyy
# They still consider it beta in 2026 they have had 20+ years to test it but whyyyyyy
# I can't even put a emoji in the file name without it breaking :( but whyyyyyy
# How can we not figure out how to do UTF-8 correctly in 2026 but whyyyyyy
# not like it's a new thing, it's been around for decades but whyyyyyy

gsudo cache on
gsudo {
  $CodePageProperties = @{
    ACP   = 65001
    MACCP = 65001
    OEMCP = 65001
  }
  foreach ($Item in $CodePageProperties.Keys) {
    New-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage' -Name $Item -PropertyType String -Value $CodePageProperties[$Item] -Force  }
}
