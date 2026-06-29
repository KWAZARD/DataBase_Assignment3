create or replace function calculate_order_total(p_order_id int)
returns numeric as $$
declare
    total numeric;
begin
    select coalesce(sum(oi.quantity * oi.price), 0) into total
    from order_items oi
    where oi.order_id = p_order_id;
    
    return total;
end;
$$ language plpgsql;



create or replace procedure create_order(p_customer_id int)
language plpgsql
as $$
declare
    new_order_id int;
    new_date timestamp := clock_timestamp();
begin
    if not exists (select 1 from customers where customer_id = p_customer_id) then
        raise exception 'customer with id % does not exist', p_customer_id;
    end if;

    new_order_id := nextval('orders_order_id_seq');
    
    insert into orders (order_id, customer_id, order_date, total_amount)
    values (new_order_id, p_customer_id, new_date, 0);
end;
$$;


create or replace procedure add_product_to_order(p_order_id int, p_product_id int, p_quantity int)
language plpgsql
as $$   
declare
    product_price numeric;
    current_stock int;
begin
    if not exists (select 1 from orders where order_id = p_order_id) then
        raise exception 'Order with id % does not exist', p_order_id;
    end if;
    
    select price, stock_quantity into product_price, current_stock 
    from products 
    where product_id = p_product_id;

    if product_price is null then
        raise exception 'Product with id % does not exist', p_product_id;
    end if;

    if p_quantity <= 0 then
        raise exception 'Quantity must be greater than 0';
    end if;

    if current_stock - p_quantity < 0 then
        raise exception 'Insufficient stock for product with id %', p_product_id;
    end if;

    insert into order_items(order_id, product_id, quantity, price)
    values (p_order_id, p_product_id, p_quantity, product_price);
    
    update products set stock_quantity = stock_quantity - p_quantity
    where product_id = p_product_id;
end;
$$;



create or replace function recalculate_total()
returns trigger as $$
declare
    v_order_id int;
begin
    if tg_op = 'delete' then
        v_order_id := old.order_id;
    else
        v_order_id := new.order_id;
    end if;

    update orders 
    set total_amount = calculate_order_total(v_order_id)
    where order_id = v_order_id;

    return null;
end;
$$ language plpgsql;



drop trigger if exists trigger_recalculate_order_total on order_items;

create trigger trigger_recalculate_order_total
after insert or update or delete on order_items
for each row
execute function recalculate_total();


create or replace function log_order()
returns trigger as $$
begin
    insert into order_log (order_id, customer_id, action)
    values (new.order_id, new.customer_id, 'created');
    return new;
end;
$$ language plpgsql;



drop trigger if exists log_order_creation_trigger on orders;

create trigger log_order_creation_trigger
after insert on orders
for each row
execute function log_order();


--=================Main script=================


CALL create_order(1);



CALL add_product_to_order(5, 3, 49);


EXPLAIN ANALYZE
SELECT
    oi.order_id,
    p.product_name,
    oi.quantity,
    oi.price,
    oi.quantity * oi.price AS item_total
FROM order_items oi
JOIN products p ON oi.product_id = p.product_id
WHERE oi.order_id = 1;






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