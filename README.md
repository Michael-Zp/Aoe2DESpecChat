# Aoe2DESpecChat
  * This is a test to enable spec chat in AoE 2 DE. It is janky and definitly not a good solution, but it kind of works.
  * My code is also jank so please don't judge. (Or do if you want, I am a README not a law.)

# How to install
  ## All:
  * Download the latest release from this repo (should be on the right side of this website)
  * Optional: Install the mod SPEC CHAT MOD NAME in your game from the mod launcher (if not already done)
    * This will make it easier to start the programs from within the game instead of going through the explorer
  * Drop every .exe file and .ps1 file from the SpecChat folder into the root directory of AoE2 DE (same directory as e.g. AoE2DE_s.exe; steam_api.dll...)
    * If you have trouble finding it, right click in steam on the game, Properties, Local Files, Browse
  * If you don't want to trust me and want to confirm that I don't just install malware on your system look below.

  ## Trust check:
  * The powershell scripts do the heavy lifting and the exe files are just to start them (I can't start ps1 scripts from within the game thus the need for exes)
  * You can take a look at the scripts. Nothing fishy is going on in there.
  * If you also don't want to use the exes, as you can not look into them, just take a look at the scripts in the Starters folder.
  * You can take these scripts and compile them with this Tool https://github.com/MScholtes/PS2EXE/archive/master.zip from this repo https://github.com/MScholtes/PS2EXE and it will work just fine as long as the file names are the same.
  * Also the code of the server that reroutes the chat is in the Server folder, if you want to take a look at that too.

# How to run
  * After placing the exes in the right directory (AoE2 DE root dir) start the game.
  * Now you start the programs from the main menu. There will be no feedback if they are started correctly so just press it once and it should work.

# Why like this
  * Exes
    * I am using the Hyperlink GUI element inside the UI of AoE 2 DE. This allows me to open certain links e.g. websites or even local files.
    * Sadly I cannot start any program with a parameter so it is not possible to start a powershell instance with a script attached, that is why I use exes.
    * Why no .bat file you ask? For some reason batch files only start if a full path is used. (So starting from the drive letter C/D/H and so on)
    * This would make it even harder to use as for the exe files I can use relative pathing. Otherwise the user might aka you might have to create ceratin folders and this is too much of a hassle honestly.

  * Why not only use a mod.
    * Well because I can not, and should not be able to, ship any executable code with a mod. This would be a security hazard so it is good as it is.
    * The only possible way I found to do it without additional code is by leveraging the Hyperlink in the UI and sending messages to a Rest webservice.
    * This requires some things tho I was not able to do:
      1. Building the rest webrequest.
        * It is possible to use bindings in the wpf to enter a URL into a hyperlink that can be opened, but I did not find a way to combine this with other strings.
        * So if I write 'www.google.com' into a textbox, I can open it. But if I just write 'google' I can not add the strings 'www.' and '.com' to it. 
          * For this I tried StringFormat or ContentStringFormat but both were not working in the game.
      2. Sending the web request with an update on the chat box

    * So this idea would boil down to these steps:
      1. Have a binding in the wpf that would trigger a web request if the chat box in game is updated.
      2. This web request would append the chat content to a request to a rest webservice which would then reroute the chat to spectators.
      3. These requests could be sorted by game code if this is somewhere available in the UI so it would look like:
        * www.xyz.com/?id=123456789&player=2&chatlog=Message
        * This would be a message from the game 12345789 from player 2 with the content 'Message'
    * So yeah as long as there is no way trigger it and form the request this will be hard.
    * Maybe instead of going on update of the chat box it would be possible to catch the 'Enter' press from the speaking player?
    * I don't know hit me with ideas if anyone has some.