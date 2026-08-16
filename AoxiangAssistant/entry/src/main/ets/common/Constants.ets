export class Constants {
  static readonly EDUCATION_SSO: string = 'https://jwxt.nwpu.edu.cn/student/sso-login';
  static readonly ELECTRICITY_SSO: string =
    'https://yktapp.nwpu.edu.cn/berserker-auth/cas/login/supwisdom?targetUrl=https%3A%2F%2Fyktapp.nwpu.edu.cn%2Fplat';
  static readonly ELECTRICITY_HOME: string = 'https://yktapp.nwpu.edu.cn/plat/shouyeUser';
}

export class LoginPhase {
  static readonly CREDENTIALS_REQUIRED: string = 'credentials_required';
  static readonly CREDENTIALS_ERROR: string = 'credentials_error';
  static readonly CREDENTIALS_SUBMITTING: string = 'credentials_submitting';
  static readonly SMS_REQUIRED: string = 'sms_required';
  static readonly SMS_SUBMITTING: string = 'sms_submitting';
  static readonly CLICKED: string = 'clicked';
  static readonly PAGE: string = 'page';
  static readonly WAITING: string = 'waiting';
  static readonly DATA: string = 'data';
  static readonly SCHEDULE_DATA: string = 'schedule_data';
  static readonly ELECTRICITY_DATA: string = 'electricity_data';
}

export class LoginTarget {
  static readonly GRADES: string = 'grades';
  static readonly SCHEDULE: string = 'schedule';
  static readonly ELECTRICITY: string = 'electricity';
}
