class WCourse {
  time: string = '';
  name: string = '';
  loc: string = '';
  color: string = '#1E88E5';
}

class WDay {
  label: string = '';
  date: string = '';
  today: boolean = false;
  empty: boolean = true;
  courses: WCourse[] = [];
}

class WData {
  title: string = '每周课表';
  hint: string = '';
  empty: boolean = true;
  days: WDay[] = [];
}

const weeklyStorage = new LocalStorage();

@Entry(weeklyStorage)
@Component
struct WeeklyCard {
  @LocalStorageProp('cardData') @Watch('onDataChanged') cardData: string = '';
  @State title: string = '每周课表';
  @State hint: string = '';
  @State days: WDay[] = [];

  aboutToAppear(): void {
    this.parseData();
  }

  onDataChanged(propName: string): void {
    this.parseData();
  }

  private parseData(): void {
    const data: WData = new WData();
    if (this.cardData.length > 0) {
      try {
        const obj: Record<string, Object> = JSON.parse(this.cardData) as Record<string, Object>;
        data.title = (obj['title'] ?? '每周课表') as string;
        data.hint = (obj['hint'] ?? '') as string;
        data.empty = (obj['empty'] ?? true) === true;
        const rawDays: Object[] = obj['days'] as Object[];
        if (rawDays !== undefined && rawDays !== null) {
          for (let di = 0; di < rawDays.length; di++) {
            const d: Record<string, Object> = rawDays[di] as Record<string, Object>;
            const day: WDay = new WDay();
            day.label = (d['label'] ?? '') as string;
            day.date = (d['date'] ?? '') as string;
            day.today = (d['today'] ?? false) === true;
            day.empty = (d['empty'] ?? true) === true;
            const rawCourses: Object[] = d['courses'] as Object[];
            if (rawCourses !== undefined && rawCourses !== null) {
              for (let ci = 0; ci < rawCourses.length; ci++) {
                const c: Record<string, Object> = rawCourses[ci] as Record<string, Object>;
                const item: WCourse = new WCourse();
                item.time = (c['time'] ?? '') as string;
                item.name = (c['name'] ?? '') as string;
                item.loc = (c['loc'] ?? '') as string;
                item.color = (c['color'] ?? '#1E88E5') as string;
                day.courses.push(item);
              }
            }
            data.days.push(day);
          }
        }
      } catch (e) {
        console.error(`WeeklyCard parse error: ${e}`);
      }
    }
    if (data.days.length === 0) {
      const labels: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      for (let i = 0; i < labels.length; i++) {
        const day: WDay = new WDay();
        day.label = labels[i];
        day.empty = true;
        data.days.push(day);
      }
    }
    this.title = data.title;
    this.hint = data.hint;
    this.days = data.days;
  }

  @Builder
  DayColumn(day: WDay) {
    Column() {
      Row() {
        Text(day.label)
          .fontSize(8)
          .fontColor(day.today ? '#FFD54F' : Color.White)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 2 })

      if (day.courses.length > 0) {
        ForEach(day.courses, (item: WCourse, idx: number) => {
          Column() {
            Text(item.time.length > 0 ? item.time : item.name)
              .fontSize(7)
              .fontColor(Color.White)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(item.name)
              .fontSize(8)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Medium)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 1 })
          }
          .width('100%')
          .padding(3)
          .borderRadius(4)
          .backgroundColor(item.color)
          .alignItems(HorizontalAlign.Start)
          .margin({ bottom: 2 })
        }, (item: WCourse, idx: number) => `${item.name}_${item.time}_${idx}`)
      } else {
        Text('')
          .fontSize(1)
      }
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 2, right: 2 })
    .height('100%')
  }

  build() {
    Column() {
      Row() {
        Text(this.title)
          .fontSize(12)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .margin({ bottom: 4 })

      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(10)
          .fontColor('#FFFFFFAA')
          .textAlign(TextAlign.Center)
          .width('100%')
          .layoutWeight(1)
      } else {
        Row({
          space: 2
        }) {
          ForEach(this.days, (day: WDay, idx: number) => {
            this.DayColumn(day)
          }, (day: WDay, idx: number) => `wday_${idx}_${day.label}`)
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Top)
      }
    }
    .width('100%')
    .height('100%')
    .padding(8)
    .backgroundColor('#1F1F1F')
    .borderRadius(12)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility'
      });
    })
  }
}