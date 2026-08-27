export class AppLogger {
  private static readonly MAX: number = 500;
  private static buffer: string[] = [];

  static info(tag: string, msg: string): void {
    const line: string = AppLogger.format('INFO', tag, msg);
    AppLogger.push(line);
    console.info(`[${tag}] ${msg}`);
  }

  static error(tag: string, msg: string): void {
    const line: string = AppLogger.format('ERROR', tag, msg);
    AppLogger.push(line);
    console.error(`[${tag}] ${msg}`);
  }

  private static push(line: string): void {
    AppLogger.buffer.push(line);
    if (AppLogger.buffer.length > AppLogger.MAX) {
      AppLogger.buffer.shift();
    }
  }

  private static format(level: string, tag: string, msg: string): string {
    const now: Date = new Date();
    const h: number = now.getHours();
    const m: number = now.getMinutes();
    const s: number = now.getSeconds();
    const ts: string = `${h < 10 ? '0' : ''}${h}:${m < 10 ? '0' : ''}${m}:${s < 10 ? '0' : ''}${s}`;
    return `${ts} [${level}] [${tag}] ${msg}`;
  }

  static exportText(): string {
    return AppLogger.buffer.join('\n');
  }

  static clear(): void {
    AppLogger.buffer = [];
  }
}
