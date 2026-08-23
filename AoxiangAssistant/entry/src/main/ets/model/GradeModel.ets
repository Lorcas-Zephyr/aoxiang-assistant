export class Grade {
  course: string = '';
  category: string = '课程';
  detail: string = '';
  credits: number = 0;
  point: number = NaN;
  score: number = NaN;
  passFailText: string = '';

  pointText(): string {
    if (this.passFailText.length > 0) {
      return this.passFailText;
    }
    return isNaN(this.point) ? '--' : this.point.toFixed(1);
  }

  scoreText(): string {
    if (this.passFailText.length > 0) {
      return this.passFailText;
    }
    return isNaN(this.score) ? '--' : this.score.toFixed(0);
  }

  static fromTableRow(cells: string[]): Grade {
    const g: Grade = new Grade();
    g.course = cells[0] ?? '';
    g.credits = parseNum(cells[1] ?? '');
    g.point = parseNum(cells[2] ?? '');
    const scoreRaw: string = cells[3] ?? '';
    const passFailMatch: RegExpMatchArray | null = scoreRaw.match(
      /^(P|NP|通过|不通过|优秀|良好|中等|及格|不及格)$/i);
    if (passFailMatch !== null) {
      g.passFailText = passFailMatch[0];
    } else {
      g.score = parseNum(scoreRaw);
    }
    g.detail = Grade.cleanDetail(cells[4] ?? '');
    g.category = '课程';
    return g;
  }

  static fromJsonObject(obj: Record<string, Object>): Grade {
    const g: Grade = new Grade();
    g.course = (obj['course'] ?? '') as string;
    g.credits = (obj['credits'] ?? 0) as number;
    const rawPoint: Object | undefined = obj['point'];
    g.point = rawPoint === null || rawPoint === undefined ? NaN : rawPoint as number;
    const rawScore: Object | undefined = obj['score'];
    g.score = rawScore === null || rawScore === undefined ? NaN : rawScore as number;
    g.category = (obj['category'] ?? '课程') as string;
    g.detail = Grade.cleanDetail((obj['detail'] ?? '') as string);
    const rawPf: Object | undefined = obj['passFailText'];
    g.passFailText = rawPf !== undefined && rawPf !== null ? (rawPf as string) : '';
    return g;
  }

  toJsonObject(): Record<string, Object> {
    const obj: Record<string, Object> = {
      'course': this.course,
      'credits': this.credits,
      'category': this.category,
      'detail': this.detail,
    };
    if (!isNaN(this.point)) {
      obj['point'] = this.point;
    }
    if (!isNaN(this.score)) {
      obj['score'] = this.score;
    }
    if (this.passFailText.length > 0) {
      obj['passFailText'] = this.passFailText;
    }
    return obj;
  }

  static cleanDetail(raw: string): string {
    let value: string = raw;
    for (let pass = 0; pass < 2; pass++) {
      value = value.replace(/&nbsp;/g, ' ')
        .replace(/&quot;/g, '"')
        .replace(/&#39;/g, "'")
        .replace(/&#x27;/g, "'")
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&amp;/g, '&');
      value = value.replace(/<br\s*\/?>/gi, ' ')
        .replace(/<[^>]*>/g, ' ');
    }
    return value.replace(/\\n/g, ' ')
      .replace(/\\r/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }
}

function parseNum(raw: string): number {
  const cleaned: string = raw.replace(/[^0-9.\-]/g, '');
  if (cleaned.length === 0) {
    return NaN;
  }
  const v: number = parseFloat(cleaned);
  return isNaN(v) ? NaN : v;
}

export class GradeMath {
  static weightedAverage(credits: number[], values: number[]): number {
    if (credits.length !== values.length) {
      return NaN;
    }
    let weighted: number = 0;
    let includedCredits: number = 0;
    for (let i = 0; i < credits.length; i++) {
      if (credits[i] > 0 && !isNaN(values[i]) && isFinite(values[i])) {
        weighted += credits[i] * values[i];
        includedCredits += credits[i];
      }
    }
    return includedCredits === 0 ? NaN : weighted / includedCredits;
  }
}
