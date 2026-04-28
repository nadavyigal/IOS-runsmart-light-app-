import Foundation

protocol RunSmartServiceProviding: TodayProviding, PlanProviding, CoachChatting, ProfileProviding, RunLogging {}

extension MockRunSmartServices: RunSmartServiceProviding {}
