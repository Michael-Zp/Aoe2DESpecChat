# Aoe2DESpecChat
  * Before using please read at least the Limitations, Prerequisites, How it works and How to install.
  * This is a test to enable spec chat in AoE 2 DE. It is janky and definitly not a good solution, but it kind of works.
  * My code is also jank so please don't judge. (Or do if you want, I am a README not a law.)
  * Here is a video link for how to install and use it: https://www.youtube.com/watch?v=a2CqNbpaFvk

# Limitations
  * Only the chat the players see, and who are running the program in the background, can be send to the spectators.

# Prerequisites
  * Both the spectator and at least one player needs the corresponding program running in the background.

# How it works
  * When a multiplayer game is started (playing or begin of spectating), the replay file is written bit by bit.
  * This replay file includes stuff like player names and of course chat, that the players can see.
  * So all the program does is read out these messages from the replay file and send them to a server.
  * The server redirects the messages to the spectators. They can be matched, because the starting portion of a replay file is unique to this replay file (at least kind of).

# How to install and use
  * Download the latest release from this repo (should be on the right side of this website)
  * Optional: Install the mod https://www.ageofempires.com/mods/details/21530/ in your game from the mod launcher (if not already done)
    * This will make it easier to start the programs from within the game instead of going through the file explorer
  * Drop every .exe file and .ps1 file from release into the root directory of AoE2 DE (same directory as e.g. AoE2DE_s.exe; steam_api.dll...)
    * If you have trouble finding it, right click in steam on the game, Properties, Local Files, Browse
  * After that you can start Age and now start either the player or spectator programs from within the game with the mod or through the file explorer.

# If you don't want to run wild exes from the internet:
  * Congratulations, you passed your first test of competency in the internet and here is how you can verify what is done in these programs.
  * The powershell scripts do the heavy lifting and the exe files are just to start them (I can't start ps1 scripts from within the game thus the need for exes)
  * You can take a look at the scripts. Nothing fishy is going on in there.
  * If you also don't want to use the exes, as you can not look into them as easily, just take a look at the scripts in the Starters folder.
  * You can take these scripts and compile them with this Tool https://github.com/MScholtes/PS2EXE/archive/master.zip from this repo https://github.com/MScholtes/PS2EXE and it will work just fine as long as the file names are the same.
  * Also the code of the server that reroutes the chat is in the Server folder, if you want to take a look at that too.
  * You can also build your own server and change the adress in the .ps1 files. Your choice.

# If you have questions why this whole thing is shitty as hell to start. Here are your answers.
  * Why exes
    * I am using the Hyperlink GUI element inside the UI of AoE 2 DE. This allows me to open certain links e.g. websites or even local files.
    * Sadly I cannot start any program with a parameter so it is not possible to start a powershell instance with a script attached, that is why I use exes.
    * Why no .bat file you ask? For some reason batch files only start if a full path is used. (So starting from the drive letter C/D/H and so on)
    * This would make it even harder to use as for the exe files I can use relative pathing. Otherwise the user aka you might have to create ceratin folders and this is too much of a hassle honestly.

  * Why starters (like start_spec_chat_player.exe)
    * Because in the player and caster scripts I have to open a TCP connection to the server, but if I do that PS2EXE will not compile the script into an exe.
    * This has a good reason, because some *insert your prefered cuss word* used PS2EXE to compile a script that contained malware and now anti virus programs recognize these exes as viruses.
    * Because of this *cuss word* the creater of PS2EXE simply implemented a check if such features were used and will not compile those scripts to prevent a further spread of false positive virus reports.
    * That's why I use the starters, because the simpler scripts are compilable.
    * Additionally with starters it is much easier to redirect output streams like errors or warnings into log files.

  * Why not only use a mod.
    * Well because I can not (and should not be able to) ship any executable code with a mod. This would be a security hazard so it is good as it is.
    * The only theoretical way I imagined to do it without additional code is by leveraging the Hyperlink in the UI and sending messages to a Rest webservice.
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
    * So yeah as long as there is no way trigger it and build the request this will be hard.
    * Maybe instead of going on update of the chat box it would be possible to catch the 'Enter' press from the speaking player?
    * I don't know hit me with ideas if anyone has some.

# Shoutouts
  * Thanks stefan-kolb for this https://github.com/stefan-kolb/aoc-mgx-format. Helped a lot with understanding the replay format.
