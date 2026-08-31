import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

class WidgetFormReg {
  formId: string = '';
  formName: string = '';
}

export class WidgetSnapshotStore {
  private static readonly STORE_NAME: string = 'widget_store';
  private static readonly REGISTRY_KEY: string = 'form_registry';
  private static readonly PREFIX: string = 'snap_';

  private static async open(context: common.Context): Promise<preferences.Preferences | undefined> {
    try {
      const options: preferences.Options = {
        name: WidgetSnapshotStore.STORE_NAME,
        storageType: preferences.StorageType.GSKV,
      };
      return await preferences.getPreferences(context, options);
    } catch (e) {
      console.error(`WidgetSnapshotStore.open error: ${e}`);
      return undefined;
    }
  }

  static async saveSnapshots(context: common.Context, snaps: Array<[string, string]>): Promise<void> {
    const pref: preferences.Preferences | undefined = await WidgetSnapshotStore.open(context);
    if (pref === undefined) {
      return;
    }
    try {
      for (let i = 0; i < snaps.length; i++) {
        pref.putSync(WidgetSnapshotStore.PREFIX + snaps[i][0], snaps[i][1]);
      }
      await pref.flush();
    } catch (e) {
      console.error(`WidgetSnapshotStore.saveSnapshots error: ${e}`);
    }
  }

  static async loadSnapshot(context: common.Context, formName: string): Promise<string> {
    const pref: preferences.Preferences | undefined = await WidgetSnapshotStore.open(context);
    if (pref === undefined) {
      return '';
    }
    try {
      return pref.getSync(WidgetSnapshotStore.PREFIX + formName, '') as string;
    } catch (e) {
      console.error(`WidgetSnapshotStore.loadSnapshot error: ${e}`);
      return '';
    }
  }

  static async registerForm(context: common.Context, formId: string, formName: string): Promise<void> {
    const pref: preferences.Preferences | undefined = await WidgetSnapshotStore.open(context);
    if (pref === undefined) {
      return;
    }
    try {
      const raw: string = pref.getSync(WidgetSnapshotStore.REGISTRY_KEY, '') as string;
      let regs: WidgetFormReg[] = [];
      if (raw.length > 0) {
        const arr: Object[] = JSON.parse(raw) as Object[];
        for (let i = 0; i < arr.length; i++) {
          const obj: Record<string, Object> = arr[i] as Record<string, Object>;
          const reg: WidgetFormReg = new WidgetFormReg();
          reg.formId = (obj['formId'] ?? '') as string;
          reg.formName = (obj['formName'] ?? '') as string;
          if (reg.formId.length > 0) {
            regs.push(reg);
          }
        }
      }
      regs = regs.filter((reg: WidgetFormReg) => reg.formId !== formId);
      const reg: WidgetFormReg = new WidgetFormReg();
      reg.formId = formId;
      reg.formName = formName;
      regs.push(reg);
      pref.putSync(WidgetSnapshotStore.REGISTRY_KEY, JSON.stringify(WidgetSnapshotStore.registryJson(regs)));
      await pref.flush();
    } catch (e) {
      console.error(`WidgetSnapshotStore.registerForm error: ${e}`);
    }
  }

  static async unregisterForm(context: common.Context, formId: string): Promise<void> {
    const pref: preferences.Preferences | undefined = await WidgetSnapshotStore.open(context);
    if (pref === undefined) {
      return;
    }
    try {
      const raw: string = pref.getSync(WidgetSnapshotStore.REGISTRY_KEY, '') as string;
      let regs: WidgetFormReg[] = [];
      if (raw.length > 0) {
        const arr: Object[] = JSON.parse(raw) as Object[];
        for (let i = 0; i < arr.length; i++) {
          const obj: Record<string, Object> = arr[i] as Record<string, Object>;
          const reg: WidgetFormReg = new WidgetFormReg();
          reg.formId = (obj['formId'] ?? '') as string;
          reg.formName = (obj['formName'] ?? '') as string;
          if (reg.formId.length > 0) {
            regs.push(reg);
          }
        }
      }
      regs = regs.filter((reg: WidgetFormReg) => reg.formId !== formId);
      pref.putSync(WidgetSnapshotStore.REGISTRY_KEY, JSON.stringify(WidgetSnapshotStore.registryJson(regs)));
      await pref.flush();
    } catch (e) {
      console.error(`WidgetSnapshotStore.unregisterForm error: ${e}`);
    }
  }

  static async findFormName(context: common.Context, formId: string): Promise<string> {
    const pref: preferences.Preferences | undefined = await WidgetSnapshotStore.open(context);
    if (pref === undefined) {
      return '';
    }
    try {
      const raw: string = pref.getSync(WidgetSnapshotStore.REGISTRY_KEY, '') as string;
      if (raw.length === 0) {
        return '';
      }
      const arr: Object[] = JSON.parse(raw) as Object[];
      for (let i = 0; i < arr.length; i++) {
        const obj: Record<string, Object> = arr[i] as Record<string, Object>;
        if ((obj['formId'] ?? '') === formId) {
          return (obj['formName'] ?? '') as string;
        }
      }
    } catch (e) {
      console.error(`WidgetSnapshotStore.findFormName error: ${e}`);
    }
    return '';
  }

  private static registryJson(regs: WidgetFormReg[]): Object[] {
    const arr: Object[] = [];
    for (let i = 0; i < regs.length; i++) {
      const obj: Record<string, Object> = {
        'formId': regs[i].formId,
        'formName': regs[i].formName,
      };
      arr.push(obj);
    }
    return arr;
  }
}
