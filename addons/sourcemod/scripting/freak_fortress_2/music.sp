#pragma semicolon 1
#pragma newdecls required

enum struct MusicEnum
{
	int Special;
	char Section[64];
	char Key[PLATFORM_MAX_PATH];
}

static ArrayList Playlist;
static char CurrentTheme[MAXTF2PLAYERS][PLATFORM_MAX_PATH];
static int CurrentVolume[MAXTF2PLAYERS];
static int CurrentSource[MAXTF2PLAYERS];
static float NextThemeAt[MAXTF2PLAYERS];
static bool DeniedByFileNet[MAXTF2PLAYERS];

void Music_PluginStart()
{
	RegFreakCmd("music", Music_Command, "Freak Fortress 2 Music Menu");
}

void Music_ClearPlaylist()
{
	delete Playlist;
	Playlist = new ArrayList(sizeof(MusicEnum));
}

void Music_AddSong(int special, const char[] section, const char[] key)
{
	MusicEnum music;
	music.Special = special;
	strcopy(music.Section, sizeof(music.Section), section);
	strcopy(music.Key, sizeof(music.Key), key);
	
	Playlist.PushArray(music);
}

void Music_BossCreated(int boss)
{
	SoundEnum sound;
	sound.Default();
	Bosses_GetRandomSound(boss, "sound_intromusic", sound);
	
	if(sound.Sound[0])
	{
		for(int client = 1; client <= MaxClients; client++)
		{
			if(!CurrentTheme[client][0] && IsClientInGame(client))
				Music_PlaySongToClient(client, sound, boss);
		}
	}
}

void Music_ClientDisconnect(int client)
{
	CurrentTheme[client][0] = 0;
	NextThemeAt[client] = 0.0;
}

void Music_RoundStart()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(NextThemeAt[i] == FAR_FUTURE)
			NextThemeAt[i] = 0.0;
	}
}

void Music_RoundEnd(int[] clients, int amount, int winner)
{
	for(int i; i < amount; i++)
	{
		if(CurrentTheme[clients[i]][0])
		{
			Music_PlaySongToClient(clients[i]);
			
			int boss;
			SoundEnum sound;
			sound.Default();
			if(Client(clients[i]).MusicShuffle)
			{
				ConfigMap cfg = Bosses_GetConfig(CurrentSource[clients[i]]);
				if(cfg)
				{
					if(GetClientTeam(clients[i]) == winner)
					{
						Bosses_GetRandomSoundCfg(cfg, "sound_outtromusic_win", sound);
					}
					else if(winner || !Bosses_GetRandomSoundCfg(cfg, "sound_outtromusic_stalemate", sound))
					{
						Bosses_GetRandomSoundCfg(cfg, "sound_outtromusic_lose", sound);
					}
					
					if(!sound.Sound[0])
						Bosses_GetRandomSoundCfg(cfg, "sound_outtromusic", sound);
				}
			}
			else
			{
				boss = GetClientOfUserId(CurrentSource[clients[i]]);
				if(boss)
				{
					if(GetClientTeam(boss) == winner)
					{
						Bosses_GetRandomSound(boss, "sound_outtromusic_win", sound);
					}
					else if(winner || !Bosses_GetRandomSound(boss, "sound_outtromusic_stalemate", sound))
					{
						Bosses_GetRandomSound(boss, "sound_outtromusic_lose", sound);
					}
					
					if(!sound.Sound[0])
						Bosses_GetRandomSound(boss, "sound_outtromusic", sound);
				}
			}
			
			if(sound.Sound[0])
				Music_PlaySongToClient(clients[i], sound, boss);
		}
	}
}

void Music_PlayerRunCmd(int client)
{
	if(RoundStatus != 2 && NextThemeAt[client] < GetGameTime())
		Music_PlayNextSong(client);
}

void Music_PlayNextSong(int client = 0)
{
	if(client)
	{
		NextThemeAt[client] = FAR_FUTURE;

		if(!Client(client).MusicShuffle)
		{
			DeniedByFileNet[client] = false;

			if(!Client(client).IsBoss || !ForwardOld_OnMusicPerBoss(client) || !Bosses_PlaySoundToClient(client, client, "sound_bgm"))
			{
				for(int i; i < MaxClients; i++)
				{
					int boss = FindClientOfBossIndex(i);
					if(boss != -1 && Bosses_PlaySoundToClient(boss, client, "sound_bgm"))
						break;
				}
			}
		}

		// If we have shuffle enabled, or we tried to play a music that client doesn't have yet
		if(Client(client).MusicShuffle || DeniedByFileNet[client])
		{
			int length = Playlist.Length;
			if(length > 0)
			{
				// Look through the playlist for a song we can play

				MusicEnum music;
				int start = GetURandomInt() % length;
				int i = start;
				do
				{
					Playlist.GetArray(i, music);
					
					ConfigMap cfg = Bosses_GetConfig(music.Special);
					if(cfg)
					{
						SoundEnum sound;
						sound.Default();
						if(Bosses_GetSpecificSoundCfg(cfg, music.Section, music.Key, sizeof(music.Key), sound) && FileNet_HasFile(client, sound.FileNet))
						{
							Music_PlaySongToClient(client, sound, music.Special);
							return;
						}
					}

					i++;
					if(i >= length)
						i = 0;
				}
				while(i != start);
			}
		}
	}
	else
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i))
				Music_PlayNextSong(i);
		}
	}
}

void Music_PlaySong(const int[] clients, int numClients, SoundEnum sound = {}, int source = 0)
{
	for(int i; i < numClients; i++)
	{
		if(CurrentTheme[clients[i]][0])
		{
			for(int a; a < CurrentVolume[clients[i]]; a++)
			{
				StopSound(clients[i], SNDCHAN_STATIC, CurrentTheme[clients[i]]);
			}
		}
	}
	
	if(sound.Sound[0])
	{
		char songName[64];
		if(sound.Name[0])
			strcopy(songName, sizeof(songName), sound.Name);
		
		char songArtist[64];
		if(sound.Artist[0])
			strcopy(songArtist, sizeof(songArtist), sound.Artist);
		
		float time = sound.Time;
		char sample2[PLATFORM_MAX_PATH];
		strcopy(sample2, sizeof(sample2), sound.Sound);
		ForwardOld_OnMusic(sample2, time, songName, songArtist, clients[0]);
		
		if(time)
		{
			time += GetGameTime();
		}
		else
		{
			time = FAR_FUTURE;
		}
		
		int count = RoundToCeil(sound.Volume);
		float vol = sound.Volume / float(count);
		
		int[] clients2 = new int[numClients];
		int amount;

		bool noName = !songName[0];
		bool noArtist = !songArtist[0];
		
		for(int i; i < numClients; i++)
		{
			DeniedByFileNet[clients[i]] = !FileNet_HasFile(clients[i], sound.FileNet);
			if(DeniedByFileNet[clients[i]])
				continue;
			
			if(songName[0] || songArtist[0])
			{
				if(noName)
					FormatEx(songName, sizeof(songName), "{default}%T", "Unknown Song", clients[i]);
				
				if(noArtist)
					FormatEx(songArtist, sizeof(songArtist), "{default}%T", "Unknown Artist", clients[i]);
				
				FPrintToChat(clients[i], "%t", "Now Playing", songArtist, songName);
			}
			
			if(!Client(clients[i]).NoMusic)
			{
				clients2[amount++] = clients[i];
				strcopy(CurrentTheme[clients[i]], sizeof(CurrentTheme[]), sample2);
				NextThemeAt[clients[i]] = time;
				CurrentVolume[clients[i]] = count;
				CurrentSource[clients[i]] = source;
			}
		}
		
		for(int i; i < count; i++)
		{
			EmitSound(clients2, amount, sample2, _, SNDCHAN_STATIC, SNDLEVEL_NONE, _, vol, sound.Pitch);
		}
	}
	else
	{
		for(int i; i < numClients; i++)
		{
			CurrentTheme[clients[i]][0] = 0;
			NextThemeAt[clients[i]] = FAR_FUTURE;
		}
	}
}

void Music_PlaySongToClient(int client, SoundEnum sound = {}, int source = 0)
{
	int clients[1];
	clients[0] = client;
	Music_PlaySong(clients, 1, sound, source);
}

void Music_PlaySongToAll(SoundEnum sound = {}, int source = 0)
{
	int[] clients = new int[MaxClients];
	int total;
	
	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client))
			clients[total++] = client;
	}
	
	Music_PlaySong(clients, total, sound, source);
}

static Action Music_Command(int client, int args)
{
	if(client)
	{
		if(args > 0)
		{
			char buffer[16];
			GetCmdArg(1, buffer, sizeof(buffer));
			
			if(StrContains(buffer, "#", false) == 0)
			{
				int index = StringToInt(buffer[1]);
				if(index >= 0 && index < Playlist.Length)
				{
					MusicEnum music;
					Playlist.GetArray(index, music);
					
					ConfigMap cfg = Bosses_GetConfig(music.Special);
					if(cfg)
					{
						SoundEnum sound;
						sound.Default();
						if(Bosses_GetSpecificSoundCfg(cfg, music.Section, music.Key, sizeof(music.Key), sound))
						{
							Client(client).MusicShuffle = true;
							
							bool toggle = Client(client).NoMusic;
							Client(client).NoMusic = false;
							Music_PlaySongToClient(client, sound, music.Special);
							Client(client).NoMusic = toggle;
						}
					}
				}
				else
				{
					FReplyToCommand(client, "%t", "Music Unknown Arg", buffer);
				}
			}
			else if(StrContains(buffer, "on", false) != -1 || StrEqual(buffer, "1") || StrContains(buffer, "enable", false) != -1)
			{
				Client(client).NoMusic = false;
				if(Enabled && RoundStatus == 1)
					Music_PlayNextSong(client);
			}
			else if(StrContains(buffer, "off", false) != -1 || StrEqual(buffer, "0") || StrContains(buffer, "disable", false) != -1)
			{
				Client(client).NoMusic = true;
				Music_PlaySongToClient(client);
				FReplyToCommand(client, "%t", "Music Disabled");
			}
			else if(StrContains(buffer, "skip", false) != -1 || StrContains(buffer, "next", false) != -1)
			{
				Client(client).MusicShuffle = false;
				
				bool toggle = Client(client).NoMusic;
				Client(client).NoMusic = false;
				Music_PlayNextSong(client);
				Client(client).NoMusic = toggle;
			}
			else if(StrContains(buffer, "shuffle", false) != -1 || StrContains(buffer, "rand", false) != -1)
			{
				Client(client).MusicShuffle = true;
				
				bool toggle = Client(client).NoMusic;
				Client(client).NoMusic = false;
				Music_PlayNextSong(client);
				Client(client).NoMusic = toggle;
			}
			else if(StrContains(buffer, "track", false) != -1 || StrContains(buffer, "list", false) != -1)
			{
				if(!client)
				{
					MusicEnum music;
					int length = Playlist.Length;
					for(int i; i < length; i++)
					{
						Playlist.GetArray(i, music);
						
						ConfigMap cfg = Bosses_GetConfig(music.Special);
						if(cfg)
						{
							SoundEnum sound;
							sound.Default();
							if(Bosses_GetSpecificSoundCfg(cfg, music.Section, music.Key, sizeof(music.Key), sound) && FileNet_HasFile(client, sound.FileNet))
							{
								IntToString(i, music.Section, sizeof(music.Section));
								
								if(!sound.Name[0])
									Format(sound.Name, sizeof(sound.Name), "%T", "Unknown Song", client);
								
								if(!sound.Artist[0])
									Format(sound.Artist, sizeof(sound.Artist), "%T", "Unknown Artist", client);
								
								int time = RoundToFloor(sound.Time);
								CRemoveTags(sound.Artist, sizeof(sound.Artist));
								CRemoveTags(sound.Name, sizeof(sound.Name));
								PrintToServer("#%d %s - %s (%d:%02d)", i, sound.Artist, sound.Name, time / 60, time % 60);
							}
						}
					}
				}
				else if(GetCmdReplySource() == SM_REPLY_TO_CONSOLE)
				{
					DataPack pack = new DataPack();
					pack.WriteCell(GetClientUserId(client));
					pack.WriteCell(0);
					RequestFrame(Music_DisplayTracks, pack);
				}
				else
				{
					Menu_Command(client);
					PlaylistMenu(client);
				}
			}
			else
			{
				FReplyToCommand(client, "%t", "Music Unknown Arg", buffer);
			}
		}
		else if(GetCmdReplySource() == SM_REPLY_TO_CONSOLE)
		{
			ReplyToCommand(client, "[SM] Usage: ff2_music <param>");
		}
		else
		{
			Menu_Command(client);
			Music_MainMenu(client);
		}
	}
	else
	{
		MusicEnum music;
		SoundEnum sound;
		int length = Playlist.Length;
		for(int i; i < length; i++)
		{
			Playlist.GetArray(i, music);
			
			sound.Default();
			ConfigMap cfg = Bosses_GetConfig(music.Special);
			if(cfg && Bosses_GetSpecificSoundCfg(cfg, music.Section, music.Key, sizeof(music.Key), sound))
			{
				if(!sound.Name[0])
					Format(sound.Name, sizeof(sound.Name), "%T", "Unknown Song", LANG_SERVER);
				
				if(!sound.Artist[0])
					Format(sound.Artist, sizeof(sound.Artist), "%T", "Unknown Artist", LANG_SERVER);
				
				int time = RoundToFloor(sound.Time);
				PrintToServer("#%d %s - %s (%d:%02d) | '%d' '%s' '%s'", i, sound.Artist, sound.Name, time / 60, time % 60, music.Special, music.Section, music.Key);
			}
			else
			{
				PrintToServer("#%d | '%d' '%s' '%s'", i, music.Special, music.Section, music.Key);
			}
		}
	}
	
	return Plugin_Handled;
}

void Music_MainMenu(int client)
{
	Menu menu = new Menu(Music_MainMenuH);
	
	SetGlobalTransTarget(client);
	menu.SetTitle("%t", "Music Menu");
	
	char buffer[64];
	FormatEx(buffer, sizeof(buffer), "%t", !Client(client).NoMusic ? Client(client).MusicShuffle ? "Music Disable" : "Music Random" : "Music Enable");
	menu.AddItem(NULL_STRING, buffer);
	
	FormatEx(buffer, sizeof(buffer), "%t", "Music Skip");
	menu.AddItem(NULL_STRING, buffer);
	
	FormatEx(buffer, sizeof(buffer), "%t", "Music Shuffle");
	menu.AddItem(NULL_STRING, buffer);
	
	FormatEx(buffer, sizeof(buffer), "%t", "Music List");
	menu.AddItem(NULL_STRING, buffer);
	
	menu.ExitButton = true;
	menu.ExitBackButton = Menu_BackButton(client);
	menu.Display(client, MENU_TIME_FOREVER);
}

static int Music_MainMenuH(Menu menu, MenuAction action, int client, int choice)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Cancel:
		{
			if(choice == MenuCancel_ExitBack)
				Menu_MainMenu(client);
		}
		case MenuAction_Select:
		{
			switch(choice)
			{
				case 0:
				{
					if(Client(client).NoMusic)
					{
						Client(client).NoMusic = false;
						Music_PlayNextSong(client);
					}
					else if(Client(client).MusicShuffle)
					{
						Client(client).MusicShuffle = false;
						Client(client).NoMusic = true;
						Music_PlaySongToClient(client);
					}
					else
					{
						Client(client).MusicShuffle = true;
						Music_PlayNextSong(client);
					}
					
					Music_MainMenu(client);
				}
				case 1:
				{
					bool toggle = Client(client).NoMusic;
					bool shuffle = Client(client).MusicShuffle;
					
					Client(client).NoMusic = false;
					Client(client).MusicShuffle = false;
					
					Music_PlayNextSong(client);
					
					Client(client).NoMusic = toggle;
					Client(client).MusicShuffle = shuffle;
					
					Music_MainMenu(client);
				}
				case 2:
				{
					bool toggle = Client(client).NoMusic;
					bool shuffle = Client(client).MusicShuffle;
					
					Client(client).NoMusic = false;
					Client(client).MusicShuffle = true;
					
					Music_PlayNextSong(client);
					
					Client(client).NoMusic = toggle;
					Client(client).MusicShuffle = shuffle;
					
					Music_MainMenu(client);
				}
				case 3:
				{
					PlaylistMenu(client);
				}
			}
		}
	}
	return 0;
}

static void PlaylistMenu(int client, int page = 0)
{
	Menu menu = new Menu(Music_PlaylistMenuH);
	
	menu.SetTitle("%t", "Music Menu");
	
	// We're just gonna use special indexes, may later use the actual config
	
	int special1 = -1;
	int special2 = -1;
	if(Client(client).IsBoss)
		Client(client).Cfg.GetInt("special", special1);
	
	if(special1 == -1 || !ForwardOld_OnMusicPerBoss(client))
	{
		for(int i; i < MaxClients; i++)
		{
			int boss = FindClientOfBossIndex(i);
			if(boss != -1 && Client(boss).Cfg.GetInt("special", special2))
				break;
		}
	}
	
	menu.AddItem("-1", " --- ", ITEMDRAW_DISABLED);
	
	MusicEnum music;
	int length = Playlist.Length;
	for(int i; i < length; i++)
	{
		Playlist.GetArray(i, music);
		
		ConfigMap cfg = Bosses_GetConfig(music.Special);
		if(cfg)
		{
			SoundEnum sound;
			sound.Default();
			if(Bosses_GetSpecificSoundCfg(cfg, music.Section, music.Key, sizeof(music.Key), sound))
			{
				IntToString(i, music.Section, sizeof(music.Section));
				
				if(!sound.Name[0])
					Format(sound.Name, sizeof(sound.Name), "%T", "Unknown Song", client);
				
				if(!sound.Artist[0])
					Format(sound.Artist, sizeof(sound.Artist), "%T", "Unknown Artist", client);
				
				int time = RoundToFloor(sound.Time);
				CRemoveTags(sound.Artist, sizeof(sound.Artist));
				CRemoveTags(sound.Name, sizeof(sound.Name));
				
				bool hasFile = FileNet_HasFile(client, sound.FileNet);
				if(hasFile)
				{
					Format(music.Key, sizeof(music.Key), "%s - %s (%d:%02d)", sound.Artist, sound.Name, time / 60, time % 60);
				}
				else
				{
					Format(music.Key, sizeof(music.Key), "%s - %s (%T)", sound.Artist, sound.Name, "Music Downloading", client);
				}

				if(music.Special == special1 || music.Special == special2)
				{
					menu.InsertItem(0, music.Section, music.Key, hasFile ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
				}
				else
				{
					menu.AddItem(music.Section, music.Key, hasFile ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
				}
			}
		}
	}
	
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.DisplayAt(client, page, MENU_TIME_FOREVER);
}

static int Music_PlaylistMenuH(Menu menu, MenuAction action, int client, int choice)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Cancel:
		{
			if(choice == MenuCancel_ExitBack)
				Music_MainMenu(client);
		}
		case MenuAction_Select:
		{
			MusicEnum music;
			menu.GetItem(choice, music.Section, sizeof(music.Section));
			int index = StringToInt(music.Section);
			if(index >= 0 && index < Playlist.Length)
			{
				Playlist.GetArray(index, music);
				
				ConfigMap cfg = Bosses_GetConfig(music.Special);
				if(cfg)
				{
					SoundEnum sound;
					sound.Default();
					if(Bosses_GetSpecificSoundCfg(cfg, music.Section, music.Key, sizeof(music.Key), sound))
					{
						bool toggle = Client(client).NoMusic;
						Client(client).NoMusic = false;
						Music_PlaySongToClient(client, sound, music.Special);
						Client(client).NoMusic = toggle;
					}
				}
			}
			
			PlaylistMenu(client, choice / 7 * 7);
		}
	}
	return 0;
}

static void Music_DisplayTracks(DataPack pack)
{
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	if(client)
	{
		int index = pack.ReadCell();
		int length = Playlist.Length;
		if(index < length)
		{
			MusicEnum music;
			Playlist.GetArray(index, music);
			
			ConfigMap cfg = Bosses_GetConfig(music.Special);
			if(cfg)
			{
				SoundEnum sound;
				sound.Default();
				if(Bosses_GetSpecificSoundCfg(cfg, music.Section, music.Key, sizeof(music.Key), sound))
				{
					if(!sound.Name[0])
						Format(sound.Name, sizeof(sound.Name), "%T", "Unknown Song", client);
					
					if(!sound.Artist[0])
						Format(sound.Artist, sizeof(sound.Artist), "%T", "Unknown Artist", client);
					
					int time = RoundToFloor(sound.Time);
					CRemoveTags(sound.Artist, sizeof(sound.Artist));
					CRemoveTags(sound.Name, sizeof(sound.Name));

					if(FileNet_HasFile(client, sound.FileNet))
					{
						PrintToConsole(client, "#%d %s - %s (%d:%02d)", index, sound.Artist, sound.Name, time / 60, time % 60);
					}
					else
					{
						PrintToConsole(client, "#%d %s - %s (%T)", index, sound.Artist, sound.Name, "Music Downloading", client);
					}
				}
			}
			
			pack.Position--;
			pack.WriteCell(index+1, false);
			RequestFrame(Music_DisplayTracks, pack);
			return;
		}
	}
	
	delete pack;
}
