import Foundation

enum DateInsertionFormat: String, CaseIterable, Identifiable {
    case monthDayYear
    case monthDayYearDashed
    case weekdayMonthDayYear
    case iso8601

    var id: String { rawValue }

    func formattedDate(from date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.calendar = Calendar.current
        formatter.dateFormat = dateFormatString
        return formatter.string(from: date)
    }

    private var dateFormatString: String {
        switch self {
        case .monthDayYear:
            return "M/d/yyyy"
        case .monthDayYearDashed:
            return "M-d-yyyy"
        case .weekdayMonthDayYear:
            return "EEEE, MMMM d, yyyy"
        case .iso8601:
            return "yyyy-MM-dd"
        }
    }
}

struct DateInsertionRequest: Identifiable, Equatable {
    let id: UUID = UUID()
    let format: DateInsertionFormat
}

enum TimeInsertionFormat: String, CaseIterable, Identifiable {
    case twentyFourHour
    case twelveHour

    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .twentyFourHour:
            return "HH:MM"
        case .twelveHour:
            return "hh:mm:AM/PM"
        }
    }

    func formattedTime(from date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.calendar = Calendar.current
        formatter.dateFormat = dateFormatString
        return formatter.string(from: date)
    }

        private var dateFormatString: String {
            switch self {
            case .twentyFourHour:
                return "HH:mm"
            case .twelveHour:
                return "h:mm a"
            }
        }
    }

struct TimeInsertionRequest: Identifiable, Equatable {
    let id: UUID = UUID()
    let format: TimeInsertionFormat
}
