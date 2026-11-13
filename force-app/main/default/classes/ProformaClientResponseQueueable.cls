public without sharing class ProformaClientResponseQueueable
    implements Queueable {

    private Id invoiceId;
    private String statusValue;
    private String comments;
    private String secureToken;


    /*
     * =========================================================
     * CONSTRUCTOR
     * =========================================================
     */
    public ProformaClientResponseQueueable(
        Id invoiceId,
        String statusValue,
        String comments,
        String secureToken
    ) {

        this.invoiceId =
            invoiceId;

        this.statusValue =
            statusValue;

        this.comments =
            comments;

        this.secureToken =
            secureToken;
    }


    /*
     * =========================================================
     * EXECUTE
     * =========================================================
     */
    public void execute(
        QueueableContext context
    ) {

        /*
         * Invoice ID must exist.
         */
        if (invoiceId == null) {
            return;
        }


        /*
         * Status must exist.
         */
        if (String.isBlank(statusValue)) {
            return;
        }


        /*
         * =====================================================
         * GET PROFORMA IN SYSTEM MODE
         * =====================================================
         */
        List<Proforma_Invoice__c> invoices =
            Database.query(
                'SELECT ' +
                    'Id, ' +
                    'Status__c, ' +
                    'Client_Comments__c, ' +
                    'Secure_Token__c ' +
                'FROM Proforma_Invoice__c ' +
                'WHERE Id = :invoiceId ' +
                'LIMIT 1',
                AccessLevel.SYSTEM_MODE
            );


        if (invoices.isEmpty()) {
            return;
        }


        Proforma_Invoice__c invoice =
            invoices[0];


        /*
         * =====================================================
         * UPDATE STATUS
         * =====================================================
         */
        invoice.Status__c =
            statusValue;


        /*
         * =====================================================
         * UPDATE CLIENT COMMENTS
         * =====================================================
         */
        if (!String.isBlank(comments)) {

            invoice.Client_Comments__c =
                comments.trim();
        }


        /*
         * =====================================================
         * PRESERVE SECURE TOKEN
         * =====================================================
         *
         * Keep the existing token after approval/change request
         * so Flutter can still reopen and display the Proforma.
         */
        if (!String.isBlank(secureToken)) {

            invoice.Secure_Token__c =
                secureToken.trim();
        }


        /*
         * =====================================================
         * SYSTEM MODE UPDATE
         * =====================================================
         */
        Database.update(
            invoice,
            AccessLevel.SYSTEM_MODE
        );
    }
}