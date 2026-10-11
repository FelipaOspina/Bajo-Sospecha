import { randomUUID } from 'node:crypto';
import { createServer, type IncomingMessage, type Server, type ServerResponse } from 'node:http';
import { WebSocketServer } from 'ws';
import type { ClientIntent } from '../../../shared/protocol/protocol.js';
import type { GameGateway } from './GameGateway.js';

/** Rutas HTTP de comprobación de salud (Render y otros hostings las consultan). */
export const HEALTH_PATHS = ['/', '/health', '/healthz'];

/**
 * Transporte WebSocket: JSON por mensaje. Solo traduce bytes ⇄ intenciones; el
 * enrutado (menú, salas, matchmaking) vive en GameGateway y la partida en Room.
 *
 * Escucha en un servidor HTTP propio en el puerto PORT: las peticiones normales a /,
 * /health o /healthz responden 200 con {"status":"ok"} (health check del hosting) y las
 * que piden "Upgrade: websocket" pasan a ser conexiones del juego. En producción el
 * hosting pone el TLS delante (wss://), así que aquí basta con HTTP.
 */
export class WsServer {
  private wss: WebSocketServer | null = null;
  private http: Server | null = null;

  constructor(private readonly port: number, private readonly gateway: GameGateway) {}

  listen(): WebSocketServer {
    const http = createServer((req, res) => this.health(req, res));
    const wss = new WebSocketServer({ server: http });
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
    this.http = http;
    http.listen(this.port);
    console.log(`Servidor escuchando en el puerto ${this.port} (ws://localhost:${this.port} · salud en /health)`);
    return wss;
  }

  private health(req: IncomingMessage, res: ServerResponse): void {
    const path = (req.url ?? '/').split('?')[0] ?? '/';
    if ((req.method === 'GET' || req.method === 'HEAD') && HEALTH_PATHS.includes(path)) {
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
      res.end(req.method === 'HEAD' ? undefined : JSON.stringify({ status: 'ok', uptimeSeconds: Math.round(process.uptime()) }));
      return;
    }
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('No encontrado');
  }

  close(): Promise<void> {
    return new Promise((resolve) => {
      const http = this.http;
      const done = () => {
        if (!http) return resolve();
        http.closeAllConnections();
        http.close(() => resolve());
      };
      if (this.wss) this.wss.close(() => done()); else done();
    });
  }
}
