if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole("Administrators")) { Start-Process powershell.exe "-File `"$PSCommandPath`"" -Verb RunAs; exit }
New-Item -Type SymbolicLink C:\Users\slugg\AppData\Roaming\alacritty\alacritty.yml -Value C:\Users\slugg\dotfiles\.config\alacritty\alacritty.yml