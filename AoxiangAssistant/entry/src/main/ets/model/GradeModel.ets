export class Grade {
  course: string = '';
  category: string = '课程';
  detail: string = '';
  credits: number = 0;
  point: number = NaN;
  score: number = NaN;

  pointText(): string {
    return isNaN(this.point) ? '--' : this.point.toFixed(1);
  }

  scoreText(): string {
    return isNaN(this.score) ? '--' : this.score.toFixed(0);
  }

  static fromTableRow(cells: string[]): Grade {
    const g: Grade = new Grade();
    g.course = cells[0] ?? '';
    g.credits = parseNum(cells[1] ?? '');
    g.point = parseNum(cells[2] ?? '');
    g.score = parseNum(cells[3] ?? '');
    g.detail = cells[4] ?? '';
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
    g.detail = (obj['detail'] ?? '') as string;
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
    return obj;
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
