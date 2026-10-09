# Final Drop Point Logistics Database Model

## Core organization

- `core.dim_drop_point` - Drop Point master.
- `core.dim_unit` - Management, Seller, Inbound, Sorting, Outbound, Delivery, Customer Service.
- `core.dim_staff` - Drop Point Manager, unit PICs, and future staff.
- `core.dim_seller` - Sellers served by a Drop Point. Each seller is assigned to a Seller-unit PIC.
- `core.dim_courier` - Last-mile couriers assigned to a Drop Point.

## Facts

- `core.fact_revenue` - shipping-fee revenue per invoice. Revenue is not merchandise value or COD value.
- `core.fact_seller_target` - revenue + active-seller target for Seller-unit PICs.
- `core.fact_delivery_target` - delivery SLA target at Drop Point level.
- `core.fact_shipment` - one row per shipment.

### Shipment lifecycle

`RECEIVED -> SORTING -> READY -> IN_TRANSIT -> ARRIVED_DESTINATION -> OUT_FOR_DELIVERY -> DELIVERED`

Exception endings:

- `FAILED`
- `RETURN_TO_SELLER`

### Shipment parties

- Seller = sender/business customer.
- Receiver = receiving party; kept on the shipment rather than a receiver dimension.
- Origin Drop Point = where the seller parcel enters the network.
- Destination Drop Point = Drop Point responsible for destination / last-mile side.
- Courier = last-mile courier.

## Responsibility

Responsibility is unit-first, then staff/PIC:

- Revenue / inactive seller -> Seller unit.
- Received parcel -> Inbound.
- Sorting parcel -> Sorting.
- Ready / linehaul / capacity issue -> Outbound.
- Last-mile execution -> Delivery.
- Address / receiver / return follow-up -> Customer Service.
- Drop Point Manager is the escalation owner for the entire Drop Point.

`analytics.vw_shipment_responsibility` resolves the responsible unit, PIC, and Drop Point Manager for a shipment.

## Website access

- One `DP_MANAGER` account is created for each Drop Point Manager.
- One `REGIONAL_MANAGER` demo account is created per distinct region.
- Drop Point access is stored in `app.user_drop_point_access`.
- Regional scope is stored in `app.user_region_access`.
- Passwords are seeded separately by migration `061`; plaintext passwords are never stored.

## Apply order

1. Stop API and n8n.
2. Apply `060_final_expedition_domain.sql`.
3. Seed temporary manager passwords with `061_seed_manager_passwords.sql`.
4. Run `062_verify_final_expedition_domain.sql`.
5. Keep API/n8n off until the application layer is updated to Seller/Staff terminology.
