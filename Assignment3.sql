select * from order_log;


create function calculate_order_total(p_order_id int)
returns numeric as $$
total numeric;
begin
select coalesce(sum(oi.quantity * oi.price), 0) into total
from order_items oi
where oi.order_id = p_order_id;
return total;
end;

create procedure create_order(p_customer_id int)
language plpgsql
as $$
if not exists (select 1 from customers where customer_id = p_customer_id) then
    raise exception 'Customer with ID % does not exist', p_customer_id;
end if;
declare
    new_order_id int;
    new_date timestamp := current_timestamp;
begin
    new_order_id = select nextval('orders_order_id_seq');
    insert into orders (order_id, customer_id, order_date, total_amount)
    values (new_order_id, p_customer_id, new_date, 0);
end;






create procedure add_product_to_order(p_order_id int, p_product_id int, p_quantity int)
language plpgsql
as $$   
if not exists (select 1 from orders where order_id = p_order_id) then
    raise exception 'Order with ID % does not exist', p_order_id;
end if;
if not exists (select 1 as product from products where product_id = p_product_id) then
    raise exception 'Product with ID % does not exist', p_product_id;
end if;
if (select stock_quantity from products where product_id = p_product_id) - p_quantity <= 0 then
    raise exception 'Insufficient stock for product with ID %', p_product_id;
end if;
declare
    product_price numeric;
begin
    select price from products 
    where p_product_id = product_id into product_price;
    insert into order_items(order_id, product_id, quantity, price)
    values (p_order_id, p_product_id, p_quantity, product_price);
    update orders set total_amount = calculate_order_total(p_order_id)
    where order_id = p_order_id;
    update products set stock_quantity = stock_quantity - p_quantity
    where product_id = p_product_id;
end;








create table customers (
    customer_id serial primary key,
    full_name varchar(100) not null,
    email varchar(100) unique not null,
    balance numeric(10,2) default 0
);

create table products (
    product_id serial primary key,
    product_name varchar(100) not null,
    price numeric(10,2) not null,
    stock_quantity int not null
);

create table orders (
    order_id serial primary key,
    customer_id int references customers(customer_id),
    order_date timestamp default current_timestamp,
    total_amount numeric(10,2) default 0
);

create table order_items (
    order_item_id serial primary key,
    order_id int references orders(order_id),
    product_id int references products(product_id),
    quantity int not null,
    price numeric(10,2) not null
);

create table order_log (
    log_id serial primary key,
    order_id int,
    customer_id int,
    action varchar(50),
    log_date timestamp default current_timestamp
);