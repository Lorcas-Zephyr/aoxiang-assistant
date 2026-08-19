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
  static readonly CREDENTIALS_VALID: string = 'credentials_valid';
  static readonly SMS_REQUIRED: string = 'sms_required';
  static readonly SMS_SUBMITTING: string = 'sms_submitting';
  static readonly SMS_ERROR: string = 'sms_error';
  static readonly CLICKED: string = 'clicked';
  static readonly PAGE: string = 'page';
  static readonly WAITING: string = 'waiting';
  static readonly DATA: string = 'data';
  static readonly SCHEDULE_DATA: string = 'schedule_data';
  static readonly ELECTRICITY_DATA: string = 'electricity_data';
  static readonly INTERACTIVE_LOGIN: string = 'interactive_login';
  static readonly API_WAITING: string = 'api_waiting';
  static readonly API_UNAVAILABLE: string = 'api_unavailable';
  static readonly TARGET_ERROR: string = 'target_error';
  static readonly GRADE_API_RAW: string = 'grade_api_raw';
  static readonly SCHEDULE_API_RAW: string = 'schedule_api_raw';
  static readonly ELECTRICITY_API_RAW: string = 'electricity_api_raw';
}

export class LoginTarget {
  static readonly GRADES: string = 'grades';
  static readonly SCHEDULE: string = 'schedule';
  static readonly ELECTRICITY: string = 'electricity';
}
