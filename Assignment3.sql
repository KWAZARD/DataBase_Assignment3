
CREATE OR REPLACE FUNCTION calculate_order_total(p_order_id int)
RETURNS numeric AS $$
DECLARE
    total numeric; -- DECLARE має бути ДО begin!
BEGIN
    SELECT coalesce(sum(oi.quantity * oi.price), 0) INTO total
    FROM order_items oi
    WHERE oi.order_id = p_order_id;
    
    RETURN total;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE PROCEDURE create_order(p_customer_id int)
LANGUAGE plpgsql
AS $$
DECLARE
    new_order_id int;
    new_date timestamp := clock_timestamp();
BEGIN
    
    IF NOT EXISTS (SELECT 1 FROM customers WHERE customer_id = p_customer_id) THEN
        RAISE EXCEPTION 'Customer with ID % does not exist', p_customer_id;
    END IF;

    new_order_id := nextval('orders_order_id_seq');
    
    INSERT INTO orders (order_id, customer_id, order_date, total_amount)
    VALUES (new_order_id, p_customer_id, new_date, 0);
END;
$$;


CREATE OR REPLACE PROCEDURE add_product_to_order(p_order_id int, p_product_id int, p_quantity int)
LANGUAGE plpgsql
AS $$   
DECLARE
    product_price numeric;
    current_stock int;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM orders WHERE order_id = p_order_id) THEN
        RAISE EXCEPTION 'Order with ID % does not exist', p_order_id;
    END IF;
    
  
    SELECT price, stock_quantity INTO product_price, current_stock 
    FROM products 
    WHERE product_id = p_product_id;

    IF product_price IS NULL THEN
        RAISE EXCEPTION 'Product with ID % does not exist', p_product_id;
    END IF;

  
    IF p_quantity <= 0 THEN
        RAISE EXCEPTION 'Quantity must be greater than 0';
    END IF;

    IF current_stock - p_quantity < 0 THEN
        RAISE EXCEPTION 'Insufficient stock for product with ID %', p_product_id;
    END IF;

    -- Вставка та оновлення стоку
    INSERT INTO order_items(order_id, product_id, quantity, price)
    VALUES (p_order_id, p_product_id, p_quantity, product_price);
    
    UPDATE products SET stock_quantity = stock_quantity - p_quantity
    WHERE product_id = p_product_id;
END;
$$;



CREATE OR REPLACE FUNCTION recalculate_total()
RETURNS TRIGGER AS $$
DECLARE
    v_order_id int;
BEGIN
   
    IF TG_OP = 'DELETE' THEN
        v_order_id := OLD.order_id;
    ELSE
        v_order_id := NEW.order_id;
    END IF;

    
    UPDATE orders 
    SET total_amount = calculate_order_total(v_order_id)
    WHERE order_id = v_order_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;



DROP TRIGGER IF EXISTS trigger_recalculate_order_total ON order_items;

CREATE TRIGGER trigger_recalculate_order_total
AFTER INSERT OR UPDATE OR DELETE ON order_items
FOR EACH ROW
EXECUTE FUNCTION recalculate_total();


CREATE OR REPLACE FUNCTION log_order()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO order_log (order_id, customer_id, action)
    VALUES (NEW.order_id, NEW.customer_id, 'created');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;



DROP TRIGGER IF EXISTS log_order_creation_trigger ON orders;

CREATE TRIGGER log_order_creation_trigger
AFTER INSERT ON orders
FOR EACH ROW
EXECUTE FUNCTION log_order();



--=================Main script=================


CALL create_order(1);



CALL add_product_to_order(5, 3, 49);


SELECT * FROM orders;
SELECT * FROM order_log;
select * from order_items;
select * from products;
select * from customers;







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