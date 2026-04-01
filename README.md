# l2k_gps3d

Protótipo de GPS 3D para FiveM.

O resource:
- lê a rota ativa do jogo
- amostra posições ao longo do GPS usando `GET_POS_ALONG_GPS_TYPE_ROUTE`
- desenha uma trilha 3D com linhas e chevrons acima da pista

## Instalação

1. Copie a pasta `l2k_gps3d` para `resources`.
2. Adicione `ensure l2k_gps3d` no `server.cfg`.
3. Entre no servidor e marque um waypoint normal no mapa.

## Comandos

- `/gps3d`: liga ou desliga o GPS 3D
- `/gps3d_refresh`: força recálculo da rota

## Observações

- É um protótipo visual, não substitui o minimap do jogo.
- O script usa a rota que o GTA/FiveM já calculou.
- Se a native `GetPosAlongGpsTypeRoute` não estiver disponível no runtime, ele avisa no console.
