package com.davtro.rental.service;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;
import java.math.BigDecimal;
@Service @RequiredArgsConstructor @Slf4j
public class EmailService {
    private final JavaMailSender mailSender;
    public void sendProformaInvoice(String to, String guestName, String bookingId, BigDecimal total) {
        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setTo(to);
            message.setSubject("Faktura Proforma - DavTro Rentals - " + bookingId);
            message.setText(String.format("Witaj %s!\n\nTwoja rezerwacja zostala potwierdzona.\nNumer: %s\nKwota: %s zl\n\nFaktura proforma. Prosze o platnosc w terminie 24h.\n\nPozdrawiamy,\nZespol DavTro Rentals", guestName, bookingId, total.toString()));
            mailSender.send(message);
            log.info("Proforma sent to: {}", to);
        } catch (Exception e) { log.error("Failed to send: {}", e.getMessage()); }
    }
}
