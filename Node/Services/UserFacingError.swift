import Foundation
import Supabase

enum UserFacingError {
    /// Convert any error -- Postgres, network, decoding, custom -- into a sentence the user can act on.
    /// Default policy: never surface raw SQL state codes, never expose internal field names.
    static func message(for error: Error) -> String {
        if let postgrest = error as? PostgrestError {
            return translatePostgrest(postgrest)
        }
        let nsError = error as NSError
        switch nsError.domain {
        case NSURLErrorDomain:
            return urlErrorMessage(nsError.code)
        case "NodeService":
            return "Something went wrong on our side. Try again."
        default:
            return "Something went wrong. Try again, and if it keeps happening, contact support from Settings."
        }
    }

    private static func translatePostgrest(_ error: PostgrestError) -> String {
        let raw = error.message.lowercased()
        if raw.contains("permission denied") || raw.contains("row-level security") {
            return "You do not have access here. Ask a member to invite you."
        }
        if raw.contains("duplicate key") {
            return "Looks like that already exists. Try a different value."
        }
        if raw.contains("violates foreign key") {
            return "That item is no longer available. Pull to refresh and try again."
        }
        if raw.contains("violates not-null") {
            return "Some required information is missing. Fill out all the fields and try again."
        }
        return "Could not save that. Try again in a moment."
    }

    private static func urlErrorMessage(_ code: Int) -> String {
        switch code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return "You are offline. Reconnect and try again."
        case NSURLErrorTimedOut:
            return "The request took too long. Check your connection and try again."
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
            return "Cannot reach Node right now. Try again in a minute."
        default:
            return "Network error. Try again."
        }
    }

    /// Specific copy for the four invite-code outcomes from `join_node_by_invite_code` RPC.
    /// Centralized so JoinNodeView, share-extension flows, and any future deep-link handler all read the same.
    static func inviteCodeMessage(for result: NodeService.JoinResult) -> String? {
        switch result {
        case .joined: return nil
        case .alreadyMember: return "You are already a member of this node."
        case .invalidCode: return "That invite code is invalid or expired. Ask the person who shared it for a new one."
        case .rateLimited: return "Too many attempts. Wait an hour and try again."
        case .nodeFull: return "This node is full. Nodes cap at ten members."
        }
    }
}
