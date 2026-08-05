/**
 * Shared helpers for the Razorpay payment flow: signature verification and
 * rupee/paise conversion. Reads Key_Secret__c / Webhook_Secret__c from
 * Razorpay_Config__mdt -- these are duplicated from the Razorpay_API Named
 * Credential on purpose, because Apex cannot read a secret back out of a
 * Named Credential's External Credential principal, and signature
 * verification (unlike the outbound order-creation callout) needs the raw
 * secret value in-process for Crypto.generateMac.
 */
public without sharing class PaymentUtil {

    private static Razorpay_Config__mdt cachedConfig;

    public static Long toPaise(Decimal rupees) {
        if (rupees == null) {
            return 0L;
        }
        return (rupees.setScale(2) * 100).longValue();
    }

    public static Decimal toRupees(Long paise) {
        if (paise == null) {
            return 0;
        }
        return Decimal.valueOf(paise) / 100;
    }

    public static Boolean verifyPaymentSignature(String orderId, String paymentId, String signature) {
        if (String.isBlank(orderId) || String.isBlank(paymentId) || String.isBlank(signature)) {
            return false;
        }
        String payload = orderId + '|' + paymentId;
        String expected = hmacHex(payload, getConfig().Key_Secret__c);
        return expected != null && expected.equalsIgnoreCase(signature);
    }

    public static Boolean verifyWebhookSignature(String rawBody, String signatureHeader) {
        if (String.isBlank(rawBody) || String.isBlank(signatureHeader)) {
            return false;
        }
        String expected = hmacHex(rawBody, getConfig().Webhook_Secret__c);
        return expected != null && expected.equalsIgnoreCase(signatureHeader);
    }

    public static String getPublicKeyId() {
        return getConfig().Key_Id__c;
    }

    private static final List<String> ONES = new List<String>{
        '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
        'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
        'Seventeen', 'Eighteen', 'Nineteen'
    };
    private static final List<String> TENS = new List<String>{
        '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'
    };

    // Indian numbering system (crore/lakh/thousand), e.g. 3325000 ->
    // "Rupees Thirty Three Lakh Twenty Five Thousand Only".
    public static String amountToWords(Decimal amount) {
        if (amount == null) {
            return '';
        }
        Decimal rounded = amount.setScale(2);
        Long rupees = rounded.longValue();
        Integer paise = ((rounded - rupees) * 100).setScale(0).intValue();

        String words = 'Rupees ' + convertWholeNumberToWords(rupees);
        if (paise > 0) {
            words += ' and ' + convertBelowHundredToWords(paise) + ' Paise';
        }
        return words + ' Only';
    }

    // e.g. 3325000.00 -> "₹33,25,000.00"
    public static String formatIndianCurrency(Decimal amount) {
        if (amount == null) {
            return '';
        }
        Decimal rounded = amount.setScale(2);
        Long wholePart = rounded.longValue();
        Integer decimalPart = ((rounded - wholePart) * 100).setScale(0).intValue();

        String decimalStr = decimalPart < 10 ? '0' + decimalPart : String.valueOf(decimalPart);
        return '₹' + formatIndianGrouping(String.valueOf(wholePart)) + '.' + decimalStr;
    }

    private static String formatIndianGrouping(String digits) {
        if (digits.length() <= 3) {
            return digits;
        }
        String lastThree = digits.substring(digits.length() - 3);
        String remaining = digits.substring(0, digits.length() - 3);

        // Built least-significant-group-first (Apex's List.add(0, x) throws
        // on an empty list, so append instead and reverse afterward).
        List<String> groups = new List<String>();
        while (remaining.length() > 2) {
            groups.add(remaining.substring(remaining.length() - 2));
            remaining = remaining.substring(0, remaining.length() - 2);
        }
        if (remaining.length() > 0) {
            groups.add(remaining);
        }

        List<String> orderedGroups = new List<String>();
        for (Integer i = groups.size() - 1; i >= 0; i--) {
            orderedGroups.add(groups[i]);
        }

        return String.join(orderedGroups, ',') + ',' + lastThree;
    }

    private static String convertWholeNumberToWords(Long inputValue) {
        if (inputValue == 0) {
            return 'Zero';
        }

        List<String> parts = new List<String>();

        Long crore = inputValue / 10000000;
        inputValue = inputValue - (crore * 10000000);
        Long lakh = inputValue / 100000;
        inputValue = inputValue - (lakh * 100000);
        Long thousand = inputValue / 1000;
        inputValue = inputValue - (thousand * 1000);
        Long hundred = inputValue / 100;
        Long remainder = inputValue - (hundred * 100);

        if (crore > 0) {
            parts.add(convertBelowHundredToWords(crore.intValue()) + ' Crore');
        }
        if (lakh > 0) {
            parts.add(convertBelowHundredToWords(lakh.intValue()) + ' Lakh');
        }
        if (thousand > 0) {
            parts.add(convertBelowHundredToWords(thousand.intValue()) + ' Thousand');
        }
        if (hundred > 0) {
            parts.add(ONES[hundred.intValue()] + ' Hundred');
        }
        if (remainder > 0) {
            parts.add(convertBelowHundredToWords(remainder.intValue()));
        }

        return String.join(parts, ' ');
    }

    private static String convertBelowHundredToWords(Integer inputValue) {
        if (inputValue < 20) {
            return ONES[inputValue];
        }
        Integer tensDigit = inputValue / 10;
        Integer onesDigit = Math.mod(inputValue, 10);
        return onesDigit > 0 ? (TENS[tensDigit] + '-' + ONES[onesDigit]) : TENS[tensDigit];
    }

    private static String hmacHex(String data, String secret) {
        if (String.isBlank(secret)) {
            return null;
        }
        Blob mac = Crypto.generateMac('hmacSHA256', Blob.valueOf(data), Blob.valueOf(secret));
        return EncodingUtil.convertToHex(mac);
    }

    private static Razorpay_Config__mdt getConfig() {
        if (cachedConfig == null) {
            cachedConfig = [
                SELECT Key_Id__c, Key_Secret__c, Webhook_Secret__c
                FROM Razorpay_Config__mdt
                WHERE DeveloperName = 'Default'
                LIMIT 1
            ];
        }
        return cachedConfig;
    }
}