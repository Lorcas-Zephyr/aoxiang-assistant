class TTCourse {
  time: string = '';
  section: string = '';
  name: string = '';
  loc: string = '';
  teacher: string = '';
  color: string = '#1E88E5';
}

class TTDay {
  label: string = '';
  date: string = '';
  empty: boolean = true;
  courses: TTCourse[] = [];
}

class TTData {
  title: string = '今明课表';
  hint: string = '';
  days: TTDay[] = [];
}

const ttStorage = new LocalStorage();

@Entry(ttStorage)
@Component
struct TodayTomorrowCard {
  @LocalStorageProp('cardData') @Watch('onDataChanged') cardData: string = '';
  @State title: string = '今明课表';
  @State hint: string = '';
  @State days: TTDay[] = [];

  aboutToAppear(): void {
    this.parseData();
  }

  onDataChanged(propName: string): void {
    this.parseData();
  }

  private parseData(): void {
    const data: TTData = new TTData();
    if (this.cardData.length > 0) {
      try {
        const obj: Record<string, Object> = JSON.parse(this.cardData) as Record<string, Object>;
        data.title = (obj['title'] ?? '今明课表') as string;
        data.hint = (obj['hint'] ?? '') as string;
        const rawDays: Object[] = obj['days'] as Object[];
        if (rawDays !== undefined && rawDays !== null) {
          for (let di = 0; di < rawDays.length; di++) {
            const d: Record<string, Object> = rawDays[di] as Record<string, Object>;
            const day: TTDay = new TTDay();
            day.label = (d['label'] ?? '') as string;
            day.date = (d['date'] ?? '') as string;
            day.empty = (d['empty'] ?? true) === true;
            const rawCourses: Object[] = d['courses'] as Object[];
            if (rawCourses !== undefined && rawCourses !== null) {
              for (let ci = 0; ci < rawCourses.length; ci++) {
                const c: Record<string, Object> = rawCourses[ci] as Record<string, Object>;
                const item: TTCourse = new TTCourse();
                item.time = (c['time'] ?? '') as string;
                item.section = (c['section'] ?? '') as string;
                item.name = (c['name'] ?? '') as string;
                item.loc = (c['loc'] ?? '') as string;
                item.teacher = (c['teacher'] ?? '') as string;
                item.color = (c['color'] ?? '#1E88E5') as string;
                day.courses.push(item);
              }
            }
            data.days.push(day);
          }
        }
      } catch (e) {
        console.error(`TodayTomorrowCard parse error: ${e}`);
      }
    }
    if (data.days.length === 0) {
      const fallback: TTDay = new TTDay();
      fallback.label = '今天';
      fallback.empty = true;
      data.days.push(fallback);
    }
    this.title = data.title;
    this.hint = data.hint;
    this.days = data.days;
  }

  @Builder
  CourseItem(item: TTCourse) {
    Column() {
      Text(item.section)
        .fontSize(8)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Bold)
        .maxLines(1)
      Text(item.name)
        .fontSize(10)
        .fontColor(Color.White)
        .fontWeight(FontWeight.Medium)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 1 })
      if (item.loc.length > 0) {
        Text(item.loc)
          .fontSize(8)
          .fontColor('#FFFFFFCC')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 1 })
      }
    }
    .width('100%')
    .padding(5)
    .borderRadius(5)
    .backgroundColor(item.color)
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 3 })
  }

  @Builder
  DayColumn(day: TTDay) {
    Column() {
      Row() {
        Text(day.label)
          .fontSize(10)
          .fontColor($r('app.color.text_primary'))
          .fontWeight(FontWeight.Bold)
        if (day.date.length > 0) {
          Text(day.date)
            .fontSize(9)
            .fontColor($r('app.color.text_hint'))
            .margin({ left: 4 })
        }
      }
      .width('100%')
      .margin({ bottom: 3 })

      if (day.courses.length > 0) {
        ForEach(day.courses, (item: TTCourse, idx: number) => {
          this.CourseItem(item)
        }, (item: TTCourse, idx: number) => `${item.section}_${item.name}_${idx}`)
      } else {
        Text('暂无课程')
          .fontSize(10)
          .fontColor($r('app.color.text_hint'))
      }
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 4, right: 4 })
    .height('100%')
  }

  build() {
    Column() {
      Row() {
        Text(this.title)
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: 4 })

      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(10)
          .fontColor($r('app.color.text_hint'))
          .textAlign(TextAlign.Center)
          .width('100%')
          .layoutWeight(1)
      } else {
        Row({
          space: 4
        }) {
          ForEach(this.days, (day: TTDay, idx: number) => {
            this.DayColumn(day)
          }, (day: TTDay, idx: number) => `day_${idx}_${day.label}`)
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Top)
      }
    }
    .width('100%')
    .height('100%')
    .padding(10)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility'
      });
    })
  }
}