import Foundation
import FirebaseFirestore

// MARK: - Order Status (Unified across iOS, Android, Backend)
/// Status flow:
/// pending_payment -> confirmed -> pending_restaurant -> preparing -> ready_for_pickup
/// -> pending_delivery_decision -> restaurant_will_deliver/ready_for_pickup -> out_for_delivery -> delivered
///
/// Restaurant acceptance flow (3-minute window):
/// pending_restaurant -> (accept) -> preparing
/// pending_restaurant -> (decline) -> declined_by_restaurant
/// pending_restaurant -> (timeout) -> restaurant_timeout
///
/// Delivery decision flow (3-minute window after ready_for_pickup):
/// ready_for_pickup -> pending_delivery_decision
/// pending_delivery_decision -> (self-deliver) -> restaurant_will_deliver -> out_for_delivery
/// pending_delivery_decision -> (pass to driver) -> ready_for_pickup (driver pool)
/// pending_delivery_decision -> (timeout) -> delivery_decision_timeout -> ready_for_pickup (driver pool)
public enum OrderStatus: String, CaseIterable {
    // Payment flow
    case pendingPayment = "pending_payment"
    case confirmed = "confirmed"

    // Restaurant acceptance window (3 minutes)
    case pendingRestaurant = "pending_restaurant"
    case declinedByRestaurant = "declined_by_restaurant"
    case restaurantTimeout = "restaurant_timeout"

    // Preparation and delivery flow
    case preparing = "preparing"
    case readyForPickup = "ready_for_pickup"

    // Delivery decision window (3 minutes)
    case pendingDeliveryDecision = "pending_delivery_decision"
    case restaurantWillDeliver = "restaurant_will_deliver"
    case deliveryDecisionTimeout = "delivery_decision_timeout"

    case outForDelivery = "out_for_delivery"
    case pendingDeliveryProof = "pending_delivery_proof"
    case delivered = "delivered"
    case cancelled = "cancelled"

    // Modification flow
    case pendingModification = "pending_modification"

    /// Display name for UI
    public var displayName: String {
        switch self {
        case .pendingPayment:
            return "Pending Payment"
        case .confirmed:
            return "Order Confirmed"
        case .pendingRestaurant:
            return "Waiting for Restaurant"
        case .declinedByRestaurant:
            return "Restaurant Declined"
        case .restaurantTimeout:
            return "Restaurant Timeout"
        case .preparing:
            return "Being Prepared"
        case .readyForPickup:
            return "Ready for Pickup"
        case .pendingDeliveryDecision:
            return "Delivery Decision Pending"
        case .restaurantWillDeliver:
            return "Restaurant Delivering"
        case .deliveryDecisionTimeout:
            return "Sent to Drivers"
        case .outForDelivery:
            return "Out for Delivery"
        case .pendingDeliveryProof:
            return "Completing Delivery"
        case .delivered:
            return "Delivered"
        case .cancelled:
            return "Cancelled"
        case .pendingModification:
            return "Action Required"
        }
    }

    /// Check if order is active (not completed, cancelled, or failed)
    public var isActive: Bool {
        switch self {
        case .delivered, .cancelled, .declinedByRestaurant, .restaurantTimeout, .deliveryDecisionTimeout:
            return false
        default:
            return true
        }
    }

    /// Check if order requires restaurant action (accept/decline or delivery decision)
    public var requiresRestaurantAction: Bool {
        switch self {
        case .pendingRestaurant, .pendingDeliveryDecision:
            return true
        default:
            return false
        }
    }

    /// Check if order can be cancelled by customer
    public var canCancel: Bool {
        switch self {
        case .pendingPayment, .confirmed, .pendingRestaurant, .pendingModification:
            return true
        default:
            return false
        }
    }

    /// Check if order is in a terminal/final state
    public var isTerminal: Bool {
        switch self {
        case .delivered, .cancelled, .declinedByRestaurant, .restaurantTimeout:
            return true
        default:
            return false
        }
    }

    /// Check if customer should receive refund for this status
    public var shouldRefund: Bool {
        switch self {
        case .cancelled, .declinedByRestaurant, .restaurantTimeout:
            return true
        default:
            return false
        }
    }

    /// Create from any string status (case-insensitive)
    public static func from(_ status: String?) -> OrderStatus {
        guard let status = status?.lowercased() else { return .confirmed }

        // Direct matches
        if let match = OrderStatus.allCases.first(where: { $0.rawValue == status }) {
            return match
        }

        // Legacy/alternate mappings AND displayName mappings
        // (displayName uses spaces, rawValue uses underscores)
        switch status {
        // Raw value alternates
        case "order_placed", "placed":
            return .confirmed
        case "accepted":
            return .preparing
        case "ready":
            return .readyForPickup
        case "picked_up":
            return .outForDelivery
        case "pending_restaurant_delivery":
            return .pendingDeliveryDecision
        case "restaurant_delivering", "self_delivering":
            return .restaurantWillDeliver

        // DisplayName mappings (human-readable with spaces)
        case "pending payment":
            return .pendingPayment
        case "order confirmed":
            return .confirmed
        case "waiting for restaurant":
            return .pendingRestaurant
        case "restaurant declined":
            return .declinedByRestaurant
        case "restaurant timeout":
            return .restaurantTimeout
        case "being prepared":
            return .preparing
        case "ready for pickup":
            return .readyForPickup
        case "delivery decision pending", "pending restaurant delivery":
            return .pendingDeliveryDecision
        case "restaurant delivering":
            return .restaurantWillDeliver
        case "sent to drivers":
            return .deliveryDecisionTimeout
        case "out for delivery":
            return .outForDelivery
        case "completing delivery", "pending delivery proof":
            return .pendingDeliveryProof
        // Note: "delivered" and "cancelled" are rawValues, matched at line 134
        case "action required":
            return .pendingModification

        default:
            return .confirmed
        }
    }
}

// MARK: - Legacy Delivery Order Status (Deprecated)
@available(*, deprecated, renamed: "OrderStatus")
public typealias DeliveryOrderStatus = OrderStatus
