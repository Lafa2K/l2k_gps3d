fx_version 'cerulean'
game 'gta5'

lua54 'yes'

author 'Lafa2K + Codex'
description '3D GPS ribbon renderer for user waypoint and mission blip routes.'
version '1.2.0'

shared_scripts {
    'gpsgeoanim.config.lua'
}

client_scripts {
    'gpsgeoanim.client.lua',
    'client.lua'
}

files {
    'data/signal-power-up_sounds.dat54.rel',
    'audiodirectory/custom_sounds.awc'
}

data_file 'AUDIO_WAVEPACK'  'audiodirectory'
data_file 'AUDIO_SOUNDDATA' 'data/signal-power-up_sounds.dat'
