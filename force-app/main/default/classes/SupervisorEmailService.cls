public with sharing class SupervisorEmailService {

    public static void sendOtp(String email, String otp) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new String[]{ email });
        mail.setSubject('Arelia Supervisor Login – OTP');
        mail.setPlainTextBody(
            'Your OTP for Arelia Supervisor login is:\n\n' +
            otp +
            '\n\nThis OTP is valid for 5 minutes.\n\n' +
            'If you did not request this, please ignore.'
        );

        Messaging.sendEmail(new Messaging.SingleEmailMessage[]{ mail });
    }
}