![Brazil Banner](https://iili.io/B1x1J2e.png)

# l2k_gps3d - Prototype 3D GPS Route Renderer for FiveM

## English

A prototype 3D GPS renderer for FiveM.

[Click here to watch the demo video](https://youtu.be/uJbZZwEVIng)

This resource:
- reads the active in-game GPS route
- samples route positions using `GET_POS_ALONG_GPS_TYPE_ROUTE`
- renders a 3D trail with lines and directional chevrons above the road

### Installation

1. Copy the `l2k_gps3d` folder into your `resources` directory
2. Add `ensure l2k_gps3d` to your `server.cfg`
3. Start the server

### How to use

1. Mark a waypoint on the map
2. Enter a vehicle
3. The 3D GPS route will render using the current active route
4. Use the commands below if needed

### Commands

- `/gps3d` — toggles the 3D GPS on or off
- `/gps3d_refresh` — forces a route rebuild
- `/gps3dcolor r,g,b,a` — change color
- `/gps3dtype 1 or 2` — change type - 1 = line, 2 = rect+uvmap (ytd - png)
- `/gps3ddebug` — Native Z/ground debug tool for testing clipping, underground points, and route height behavior.

### Notes

- This is a visual prototype and does not replace the default minimap GPS
- The script uses the route already calculated by GTA/FiveM
- It includes a first pass for junction filtering and curve continuity, although some turns may still show minor visual artifacts
- If `GetPosAlongGpsTypeRoute` is unavailable in the current runtime, the script will warn in console

## License
This project is licensed under the MIT License.

## Attribution
If you use this resource as a base for your own project, please provide visible credit to the original project and author. It would be greatly appreciated.



---

## Português (BR)

Um protótipo de GPS 3D para FiveM.

[Clique aqui para assistir ao vídeo de demonstração](https://youtu.be/uJbZZwEVIng)

Este resource:
- lê a rota ativa do GPS do jogo
- amostra posições ao longo da rota usando `GET_POS_ALONG_GPS_TYPE_ROUTE`
- renderiza uma trilha 3D com linhas e chevrons direcionais acima da pista

### Instalação

1. Copie a pasta `l2k_gps3d` para o diretório `resources`
2. Adicione `ensure l2k_gps3d` ao seu `server.cfg`
3. Inicie o servidor

### Como usar

1. Marque um ponto no mapa
2. Entre em um carro
3. O GPS 3D será renderizado usando a rota ativa atual
4. Use os comandos abaixo se necessário

### Comandos

- `/gps3d` — liga ou desliga o GPS 3D
- `/gps3d_refresh` — força a reconstrução da rota
- `/gps3dcolor r,g,b,a` — change color
- `/gps3dtype 1 or 2` — muda o tipo entre linha e rectuvmap
- `/gps3ddebug` — Debug para consertar o problema de Z abaixo da pista. em teste
- 
## License
This project is licensed under the MIT License.

## Attribution
Se você usar este resource como base para o seu próprio projeto, por favor dê os devidos créditos de forma visível ao projeto original e ao autor. Isso será muito apreciado.



### Observações

- Este é um protótipo visual e não substitui o GPS padrão do minimap
- O script usa a rota que o GTA/FiveM já calculou
- Ele já inclui uma primeira tentativa de filtragem de junctions e continuidade em curvas, embora algumas curvas ainda possam apresentar pequenos artefatos visuais
- Se a native `GetPosAlongGpsTypeRoute` não estiver disponível no runtime atual, o script exibirá um aviso no console
