# pfQuest (turtle)
This AddOn is a [pfQuest](https://github.com/shagu/pfQuest) extension, which adds support for the [TurtleWoW](https://turtle-wow.org/) Private Server. In order to run this extension, the latest version of [pfQuest](https://github.com/shagu/pfQuest) is always required and only enUS-Gameclients are supported.

*Notice: Issues and bugs like "please add quest XYZ" and all other content requests will be silently ignored. This is, because the data is not manually added, but depends on the Turtle-WoW team to release their database to a trusted person that can produce pfQuest-turtle builds.*

If you wish to contribute, please feel free to send a [Pull Requests](https://github.com/shagu/pfQuest-turtle/pulls).

## Features

### Custom Quest Coloring
Custom TurtleWoW quests (Quest IDs >= 40000) are displayed in a distinctive **teal/cyan color** to differentiate them from classic World of Warcraft quests. This makes it easy to identify which quests are original content and which are custom additions by the TurtleWoW team.

- **Classic Quests** (ID < 40000): Default quest color
- **Custom Quests** (ID >= 40000): Teal/cyan color (`|cff48d1cc`)

The coloring is applied **on-demand** using lazy evaluation, which significantly improves addon load time and reduces memory usage compared to pre-coloring all quests at startup.

### Performance Optimizations
- **Lazy Quest Coloring**: Quest titles are colored dynamically when accessed, not at load time
- **Efficient Database Patching**: Only TurtleWoW-specific changes are stored and merged
- **Automatic Cache Management**: Quest cache is automatically cleared when new quests are detected

## Install
*The latest version of [pfQuest](https://shagu.org/pfQuest) is required for this module to work.*

1. Download **[pfQuest-turtle](https://github.com/shagu/pfQuest-turtle/archive/master.zip)**
2. Unpack the Zip file
3. Rename the folder "pfQuest-turtle-master" to "pfQuest-turtle"
4. Copy "pfQuest-turtle" into Wow-Directory\Interface\AddOns
5. Restart Wow
