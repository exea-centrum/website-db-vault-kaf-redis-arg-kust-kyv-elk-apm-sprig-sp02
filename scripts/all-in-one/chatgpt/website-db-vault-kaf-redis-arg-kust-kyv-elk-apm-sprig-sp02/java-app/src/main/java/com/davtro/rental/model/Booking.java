package com.davtro.rental.model;
import jakarta.persistence.*;
import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
@Entity @Table(name = "bookings") @Data
public class Booking {
    @Id private String id;
    private Integer propertyId;
    private String guestName;
    private String email;
    private String phone;
    private Integer guests;
    private LocalDate checkIn;
    private LocalDate checkOut;
    private Integer nights;
    private BigDecimal totalPrice;
    private String status;
    private String pipeline;
    private LocalDateTime createdAt;
}
