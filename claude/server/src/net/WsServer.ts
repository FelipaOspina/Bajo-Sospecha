import { randomUUID } from 'node:crypto';
import { WebSocketServer } from 'ws';
import type { ClientIntent } from '../../../shared/protocol/protocol.js';
import type { GameGateway } from './GameGateway.js';

/**
 * Transporte WebSocket: JSON por mensaje. Solo traduce bytes ⇄ intenciones; el
 * enrutado (menú, salas, matchmaking) vive en GameGateway y la partida en Room.
 */
export class WsServer {
  private wss: WebSocketServer | null = null;

  constructor(private readonly port: number, private readonly gateway: GameGateway) {}

  listen(): WebSocketServer {
    const wss = new WebSocketServer({ port: this.port });
    wss.on('connection', (ws) => {
      // TODO: autenticación real; el perfil se identifica con el id que guarda el cliente.
      const id = randomUUID();
      this.gateway.open(id, (msg) => { if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg)); });
      ws.on('message', (data) => {
        let intent: ClientIntent;
        try { intent = JSON.parse(String(data)); } catch { return; }
        if (typeof intent?.t !== 'string' || typeof intent.seq !== 'number') return;
        this.gateway.message(id, intent);
      });
      ws.on('close', () => this.gateway.close(id));
    });
    this.wss = wss;
    console.log(`Servidor escuchando en ws://localhost:${this.port}`);
    return wss;
  }

  close(): Promise<void> {
    return new Promise((resolve) => (this.wss ? this.wss.close(() => resolve()) : resolve()));
  }
}
