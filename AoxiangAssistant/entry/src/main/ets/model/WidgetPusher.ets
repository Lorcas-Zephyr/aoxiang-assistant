import { common } from '@kit.AbilityKit';
import { formProvider } from '@kit.FormKit';
import { Course, Semester } from './CourseModel';
import { WidgetDataBuilder, WidgetSnapshot } from './WidgetDataBuilder';
import { WidgetSnapshotStore } from './WidgetSnapshotStore';

export class WidgetPusher {
  static async refresh(context: common.UIAbilityContext, courses: Course[], semesters: Semester[],
                       semesterIndex: number, balance: number): Promise<void> {
    try {
      const snaps: WidgetSnapshot[] = WidgetDataBuilder.buildAll(courses, semesters, semesterIndex,
        balance, new Date());
      const pairs: Array<[string, string]> = [];
      for (let i = 0; i < snaps.length; i++) {
        pairs.push([snaps[i].formName, snaps[i].json]);
      }
      await WidgetSnapshotStore.saveSnapshots(context, pairs);
      const notified: number = await formProvider.reloadAllForms(context);
      console.info(`WidgetPusher.refresh: snapshots=${pairs.length} forms=${notified}`);
    } catch (e) {
      console.error(`WidgetPusher.refresh error: ${e}`);
    }
  }
}