import Foundation

enum Endpoint {
    case publicATSCheck
    case convertAnonymousSession
    case atsScore
    case optimize
    case optimizations
    case optimizationReview(String)
    case applyOptimizationReview(String)
    case applications
    case credits
    case designTemplates
    case customizeDesign(String)
    case assignDesign(String)
    case downloadResume(String)
    case uploadResume
    case iapVerify

    var path: String {
        switch self {
        case .publicATSCheck:
            return "/api/public/ats-check"
        case .convertAnonymousSession:
            return "/api/public/convert-session"
        case .atsScore:
            return "/api/ats/score"
        case .optimize:
            return "/api/optimize"
        case .optimizations:
            return "/api/optimizations"
        case .optimizationReview(let id):
            return "/api/v1/optimization-reviews/\(id)"
        case .applyOptimizationReview(let id):
            return "/api/v1/optimization-reviews/\(id)/apply"
        case .applications:
            return "/api/v1/applications"
        case .credits:
            return "/api/v1/credits"
        case .designTemplates:
            return "/api/v1/design/templates"
        case .customizeDesign(let optimizationId):
            return "/api/v1/design/\(optimizationId)/customize"
        case .assignDesign(let optimizationId):
            return "/api/v1/design/\(optimizationId)"
        case .downloadResume(let optimizationId):
            return "/api/download/\(optimizationId)"
        case .uploadResume:
            return "/api/upload-resume"
        case .iapVerify:
            return "/api/v1/iap/verify"
        }
    }
}
