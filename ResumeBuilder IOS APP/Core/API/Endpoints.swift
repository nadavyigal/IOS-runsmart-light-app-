import Foundation

enum Endpoint {
    case publicATSCheck
    case atsScore
    case optimize
    case applications
    case credits
    case uploadResume
    case iapVerify

    var path: String {
        switch self {
        case .publicATSCheck:
            return "/api/public/ats-check"
        case .atsScore:
            return "/api/ats/score"
        case .optimize:
            return "/api/optimize"
        case .applications:
            return "/api/v1/applications"
        case .credits:
            return "/api/v1/credits"
        case .uploadResume:
            return "/api/upload-resume"
        case .iapVerify:
            return "/api/v1/iap/verify"
        }
    }
}
