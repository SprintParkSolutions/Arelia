public without sharing class BudgetReviewClientResponseQueueable
    implements Queueable {

    private Id opportunityId;

    private String statusFieldApiName;

    private String clientRemarksFieldApiName;

    private String statusValue;

    private String comments;


    /*
     * =========================================================
     * CONSTRUCTOR
     * =========================================================
     */
    public BudgetReviewClientResponseQueueable(
        Id opportunityId,
        String statusFieldApiName,
        String clientRemarksFieldApiName,
        String statusValue,
        String comments
    ) {

        this.opportunityId =
            opportunityId;

        this.statusFieldApiName =
            statusFieldApiName;

        this.clientRemarksFieldApiName =
            clientRemarksFieldApiName;

        this.statusValue =
            statusValue;

        this.comments =
            comments;
    }


    /*
     * =========================================================
     * EXECUTE
     * =========================================================
     */
    public void execute(
        QueueableContext context
    ) {

        if (
            opportunityId == null ||
            String.isBlank(statusFieldApiName) ||
            String.isBlank(statusValue)
        ) {

            return;
        }


        List<SObject> opportunities =
            Database.query(
                'SELECT Id,' +
                statusFieldApiName +
                ',' +
                clientRemarksFieldApiName +
                ' FROM Opportunity ' +
                'WHERE Id = :opportunityId ' +
                'LIMIT 1',
                AccessLevel.SYSTEM_MODE
            );


        if (opportunities.isEmpty()) {

            return;
        }


        SObject opportunity =
            opportunities[0];


        /*
         * Update status.
         */
        opportunity.put(
            statusFieldApiName,
            statusValue
        );


        /*
         * Update remarks only if provided.
         */
        if (
            !String.isBlank(comments) &&
            !String.isBlank(
                clientRemarksFieldApiName
            )
        ) {

            opportunity.put(
                clientRemarksFieldApiName,
                comments.trim()
            );
        }


        Database.update(
            opportunity,
            AccessLevel.SYSTEM_MODE
        );
    }
}