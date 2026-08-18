/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;

const pxToVp = (px: number): number => {
  const density: number = display.getDefaultDisplaySync().densityPixels;
  return density > 0 ? Math.round(px / density) : px;
};

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      const configColorMode: ConfigurationConstant.ColorMode =
        this.context.config.colorMode ?? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      AppStorage.setOrCreate('colorMode', configColorMode);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    try {
      const win: window.Window = windowStage.getMainWindowSync();
      win.setWindowLayoutFullScreen(true).then(() => {
        hilog.info(DOMAIN, 'testTag', '%{public}s', 'Succeeded in setting the window layout to full-screen mode.');
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to set full screen. Cause: %{public}s', JSON.stringify(err));
      });

      const systemArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      AppStorage.setOrCreate('topRectHeight', pxToVp(systemArea.topRect.height));
      const navArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      AppStorage.setOrCreate('bottomRectHeight', pxToVp(navArea.bottomRect.height));

      win.on('avoidAreaChange', (data) => {
        const info: Record<string, Object> = (data as object) as Record<string, Object>;
        const typeVal: Object | undefined = info['type'];
        const areaVal: Object | undefined = info['area'];
        if (typeVal !== undefined && areaVal !== undefined && Number(typeVal) === window.AvoidAreaType.TYPE_SYSTEM) {
          const area: Record<string, Object> = areaVal as Record<string, Object>;
          const top: Record<string, Object> = area['topRect'] as Record<string, Object>;
          const h: Object | undefined = top['height'];
          if (h !== undefined) {
            AppStorage.setOrCreate('topRectHeight', pxToVp(Number(h)));
          }
        } else if (typeVal !== undefined && areaVal !== undefined && Number(typeVal) === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          const area: Record<string, Object> = areaVal as Record<string, Object>;
          const bottom: Record<string, Object> = area['bottomRect'] as Record<string, Object>;
          const h: Object | undefined = bottom['height'];
          if (h !== undefined) {
            AppStorage.setOrCreate('bottomRectHeight', pxToVp(Number(h)));
          }
        }
      });
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'Failed to configure window. Cause: %{public}s', JSON.stringify(e));
    }
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}