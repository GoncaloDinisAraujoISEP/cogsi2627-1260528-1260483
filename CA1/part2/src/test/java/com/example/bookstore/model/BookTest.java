package com.example.bookstore.model;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class BookTest {

    @Test
    void storesTitleAuthorAndPrice() {
        Book book = new Book();
        book.setTitle("Clean Code");
        book.setAuthor("Robert C. Martin");
        book.setPrice(39.90);

        assertEquals("Clean Code", book.getTitle());
        assertEquals("Robert C. Martin", book.getAuthor());
        assertEquals(39.90, book.getPrice(), 0.001);
    }

    @Test
    void newOrderStartsAsPending() {
        assertEquals(OrderStatus.PENDING, new Order().getStatus());
    }
}
