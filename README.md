# Arena 4v4 (Godot 3.5, Android)

Third-person team deathmatch 4 v 4 (wewe + 3 bots dhidi ya bots 4), touch controls, map ya "compound" yenye nyumba 2.
Mannequin character: GDQuest (MIT / CC-BY 4.0), tazama `LICENSE-mannequin.txt`.

## Jinsi ya kupata APK kupitia GitHub
1. Tengeneza repo mpya kwenye github.com (mfano `arena-4v4`).
2. Upload files zote za folder hii (pamoja na folder `.github`) kwenye branch `main`.
3. Nenda tab **Actions** -> "Build Android APK" itaanza yenyewe (au bonyeza **Run workflow**).
4. Ikimaliza (dakika 5-10), fungua run -> **Artifacts** -> download `arena-4v4-apk`, unzip, install `arena-4v4.apk` kwenye simu.

## Controls
- Kushoto: joystick (gusa popote upande wa kushoto)
- Kulia: buruta kidole kuzunguka kamera
- FIRE (shikilia), JUMP, R = reload

## Kubadilisha vitu
- `src/Main/Main.gd`: `KILLS_TO_WIN`, `MATCH_TIME`, `TEAM_SIZE`, `USE_SHADOWS`
- `src/Game/Arena.gd`: muundo wa map (COVER, houses)
- `src/Game/HumanPlayer.gd`: `SENS` (sensitivity), damage, fire rate
- `src/Game/Bot.gd`: akili ya bots

Test kwenye PC: fungua folder kwa Godot 3.5, bonyeza Play (mouse hufanya kazi kama touch; WASD + Space + R pia).
