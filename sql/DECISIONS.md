# Data decisions
- Analysis window: 2017-01-01 to 2018-08-31 (other months have too few orders).
- Delivery and satisfaction analysis: order_status = 'delivered' only, with a non-null delivery date (8 delivered orders without date excluded).
- Reviews: one review per order, keeping the latest review_creation_date.
- Customers: customer_unique_id identifies a real customer (customer_id is per order).
- Products without a category are labeled 'unknown'.
- 23 orders have customer delivery before carrier pickup: kept, noted as a data inconsistency.
