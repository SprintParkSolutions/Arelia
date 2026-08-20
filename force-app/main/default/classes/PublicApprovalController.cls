/**
 * @description Public Visualforce controller for manager quotation approval and rejection.
 */
@SuppressWarnings('PMD.ApexCRUDViolation')
public without sharing class PublicApprovalController {
    private static final String PARAM_ID = 'id';
    private static final String PARAM_PID = 'pId';
    private static final String PARAM_RECORD_ID = 'recordId';
    private static final String PARAM_QUOTE_ID = 'quoteId';
    private static final String PARAM_C_RECORD_ID = 'c__recordId';
    private static final String PARAM_C_QUOTE_ID = 'c__quoteId';

    private static final String ERROR_ID_LOST = 'System Error: Record ID is lost.';
    private static final String ERROR_ID_NOT_FOUND = 'Error: Quotation record ID could not be retrieved from the URL.';
    private static final String ERROR_INVALID_ID = 'Invalid quotation link.';
    private static final String ERROR_INVALID_QUOTATION_ID = 'Invalid Link: Quotation record ID is required.';
    private static final String ERROR_REJECTION_REQUIRED = 'Error: Please enter a reason for rejection.';

    /**
     * @description Indicates whether approval was completed in the current request.
     */
    public Boolean approved { get; set; }

    /**
     * @description Indicates whether rejection was completed in the current request.
     */
    public Boolean rejected { get; set; }

    /**
     * @description Indicates whether an error should be shown.
     */
    public Boolean hasError { get; set; }

    /**
     * @description Stores the error message shown on the page.
     */
    public String errorMessage { get; set; }

    /**
     * @description Stores the Quotation__c Id used for processing.
     */
    public Id quoteId { get; set; }

    /**
     * @description Stores quotation Id value received from the Experience Builder URL.
     */
    public String quoteIdValue { get; set; }

    /**
     * @description Stores the manager rejection reason.
     */
    public String rejectionReason { get; set; }

    /**
     * @description Controls rejection input section visibility.
     */
    public Boolean isRejecting { get; set; }

    /**
     * @description Controls approval confirmation popup visibility.
     */
    public Boolean showApproveConfirm { get; set; }

    /**
     * @description Controls rejection confirmation popup visibility.
     */
    public Boolean showRejectConfirm { get; set; }

    /**
     * @description Indicates whether this quotation link is already used.
     */
    public Boolean responseAlreadyRecorded { get; set; }

    /**
     * @description Indicates whether the page has completed initial Id loading.
     */
    public Boolean pageInitialized { get; set; }

    /**
     * @description Initializes page state.
     */
    public PublicApprovalController() {
        initializeState();
        loadDirectQuotationId();
    }

    /**
     * @description Receives quotation Id from the Visualforce page after reading the Experience Builder URL.
     */
    public void setRecordIdFromClient() {
        pageInitialized = true;

        String recordIdValue = getFirstAvailableValue(new List<String>{
            quoteIdValue,
            getDirectPageParameter()
        });

        if (!assignQuotationId(recordIdValue, ERROR_ID_NOT_FOUND)) {
            return;
        }

        loadRecordedResponseStatus();
    }

    /**
     * @description Shows approval confirmation.
     * @return Null because the page is rerendered.
     */
    public PageReference showApproveConfirmation() {
        if (!canContinueWithResponse()) {
            return null;
        }

        showApproveConfirm = true;
        showRejectConfirm = false;
        clearError();
        return null;
    }

    /**
     * @description Closes approval confirmation.
     * @return Null because the page is rerendered.
     */
    public PageReference closeApproveConfirmation() {
        showApproveConfirm = false;
        return null;
    }

    /**
     * @description Shows rejection confirmation after validating reason.
     * @return Null because the page is rerendered.
     */
    public PageReference showRejectConfirmation() {
        if (!canContinueWithResponse()) {
            return null;
        }

        if (String.isBlank(rejectionReason)) {
            setError(ERROR_REJECTION_REQUIRED);
            return null;
        }

        showRejectConfirm = true;
        showApproveConfirm = false;
        clearError();
        return null;
    }

    /**
     * @description Closes rejection confirmation.
     * @return Null because the page is rerendered.
     */
    public PageReference closeRejectConfirmation() {
        showRejectConfirm = false;
        return null;
    }

    /**
     * @description Approves the quotation.
     * @return Null because the page is rerendered.
     */
    public PageReference doApprove() {
        return saveResponse(true);
    }

    /**
     * @description Enables rejection mode.
     * @return Null because the page is rerendered.
     */
    public PageReference enableRejectMode() {
        if (!canContinueWithResponse()) {
            return null;
        }

        isRejecting = true;
        showApproveConfirm = false;
        showRejectConfirm = false;
        clearError();
        return null;
    }

    /**
     * @description Cancels rejection mode.
     * @return Null because the page is rerendered.
     */
    public PageReference cancelRejectMode() {
        isRejecting = false;
        showRejectConfirm = false;
        rejectionReason = '';
        clearError();
        return null;
    }

    /**
     * @description Rejects the quotation.
     * @return Null because the page is rerendered.
     */
    public PageReference doConfirmReject() {
        if (String.isBlank(rejectionReason)) {
            setError(ERROR_REJECTION_REQUIRED);
            return null;
        }

        return saveResponse(false);
    }

    /**
     * @description Backward-compatible rejection method.
     * @return Result of enabling rejection mode.
     */
    public PageReference doReject() {
        return enableRejectMode();
    }

    /**
     * @description Saves approval or rejection response.
     * @param isApproval True for approval and false for rejection.
     * @return Null because the page is rerendered.
     */
    private PageReference saveResponse(Boolean isApproval) {
        if (!ensureQuotationId(ERROR_ID_LOST)) {
            return null;
        }

        Quotation__c quotationRecord = getQuotationForUpdate();

        if (quotationRecord == null) {
            setError(ERROR_INVALID_QUOTATION_ID);
            return null;
        }

        if (isResponseRecorded(quotationRecord)) {
            setLinkExpiredState();
            return null;
        }

        applyResponse(quotationRecord, isApproval);
        update quotationRecord;
        setSuccessState(isApproval);
        return null;
    }

    /**
     * @description Applies approval or rejection values.
     * @param quotationRecord Quotation record.
     * @param isApproval True for approval and false for rejection.
     */
    private void applyResponse(Quotation__c quotationRecord, Boolean isApproval) {
        quotationRecord.Manager_approval__c = isApproval;

        if (isApproval) {
            quotationRecord.Rejection_Reason__c = null;
            return;
        }

        quotationRecord.Rejection_Reason__c = rejectionReason;
    }

    /**
     * @description Sets success state after first response.
     * @param isApproval True for approval and false for rejection.
     */
    private void setSuccessState(Boolean isApproval) {
        approved = isApproval;
        rejected = !isApproval;
        responseAlreadyRecorded = false;
        isRejecting = false;
        showApproveConfirm = false;
        showRejectConfirm = false;
        clearError();
    }

    /**
     * @description Checks whether the user can still submit response.
     * @return True when quotation exists and link is not already used.
     */
    private Boolean canContinueWithResponse() {
        if (!ensureQuotationId(ERROR_ID_LOST)) {
            return false;
        }

        if (hasRecordedResponse()) {
            setLinkExpiredState();
            return false;
        }

        return true;
    }

    /**
     * @description Sets default values.
     */
    private void initializeState() {
        approved = false;
        rejected = false;
        hasError = false;
        errorMessage = null;
        quoteIdValue = '';
        isRejecting = false;
        rejectionReason = '';
        showApproveConfirm = false;
        showRejectConfirm = false;
        responseAlreadyRecorded = false;
        pageInitialized = false;
    }

    /**
     * @description Loads quotation Id directly when Visualforce receives URL parameters.
     */
    private void loadDirectQuotationId() {
        String recordIdValue = getDirectPageParameter();

        if (String.isBlank(recordIdValue)) {
            return;
        }

        pageInitialized = true;

        if (assignQuotationId(recordIdValue, ERROR_INVALID_ID)) {
            loadRecordedResponseStatus();
        }
    }

    /**
     * @description Assigns quotation Id after format validation.
     * @param recordIdValue Record Id value.
     * @param errorMessageToShow Error shown when Id is invalid.
     * @return True when Id is assigned.
     */
    private Boolean assignQuotationId(String recordIdValue, String errorMessageToShow) {
        Id parsedId = parseRecordId(recordIdValue);

        if (parsedId == null) {
            setError(errorMessageToShow);
            return false;
        }

        if (parsedId.getSObjectType() != Quotation__c.SObjectType) {
            setError(ERROR_INVALID_QUOTATION_ID);
            return false;
        }

        quoteId = parsedId;
        quoteIdValue = String.valueOf(parsedId);
        clearError();
        return true;
    }

    /**
     * @description Loads already-recorded response status.
     */
    private void loadRecordedResponseStatus() {
        Quotation__c quotationRecord = getQuotation();

        if (quotationRecord == null) {
            setError(ERROR_INVALID_QUOTATION_ID);
            return;
        }

        if (isResponseRecorded(quotationRecord)) {
            setLinkExpiredState();
        }
    }

    /**
     * @description Ensures quotation Id is available.
     * @param missingIdMessage Message shown when Id is missing.
     * @return True when quotation Id exists.
     */
    private Boolean ensureQuotationId(String missingIdMessage) {
        if (quoteId != null) {
            return true;
        }

        String recordIdValue = getFirstAvailableValue(new List<String>{
            quoteIdValue,
            getDirectPageParameter()
        });

        return assignQuotationId(recordIdValue, missingIdMessage);
    }

    /**
     * @description Checks existing response status.
     * @return True when response already exists.
     */
    private Boolean hasRecordedResponse() {
        return isResponseRecorded(getQuotation());
    }

    /**
     * @description Gets quotation record.
     * @return Quotation record or null.
     */
    private Quotation__c getQuotation() {
        List<Quotation__c> quotationRecords = [
            SELECT Id, Manager_approval__c, Rejection_Reason__c
            FROM Quotation__c
            WHERE Id = :quoteId
            LIMIT 1
        ];

        return quotationRecords.isEmpty() ? null : quotationRecords[0];
    }

    /**
     * @description Gets quotation record with lock.
     * @return Quotation record or null.
     */
    private Quotation__c getQuotationForUpdate() {
        List<Quotation__c> quotationRecords = [
            SELECT Id, Manager_approval__c, Rejection_Reason__c
            FROM Quotation__c
            WHERE Id = :quoteId
            LIMIT 1
            FOR UPDATE
        ];

        return quotationRecords.isEmpty() ? null : quotationRecords[0];
    }

    /**
     * @description Checks whether quotation already has response.
     * @param quotationRecord Quotation record.
     * @return True when approval or rejection is already recorded.
     */
    private Boolean isResponseRecorded(Quotation__c quotationRecord) {
        return quotationRecord != null
            && (quotationRecord.Manager_approval__c == true
            || String.isNotBlank(quotationRecord.Rejection_Reason__c));
    }

    /**
     * @description Sets expired-link state.
     */
    private void setLinkExpiredState() {
        responseAlreadyRecorded = true;
        approved = false;
        rejected = false;
        isRejecting = false;
        showApproveConfirm = false;
        showRejectConfirm = false;
        clearError();
    }

    /**
     * @description Gets direct page parameter.
     * @return Record Id value.
     */
    private String getDirectPageParameter() {
        PageReference currentPage = ApexPages.currentPage();

        if (currentPage == null) {
            return null;
        }

        Map<String, String> pageParameters = currentPage.getParameters();

        return getFirstAvailableValue(new List<String>{
            pageParameters.get(PARAM_QUOTE_ID),
            pageParameters.get(PARAM_RECORD_ID),
            pageParameters.get(PARAM_PID),
            pageParameters.get(PARAM_ID),
            pageParameters.get(PARAM_C_QUOTE_ID),
            pageParameters.get(PARAM_C_RECORD_ID)
        });
    }

    /**
     * @description Gets first non-blank value.
     * @param values Candidate values.
     * @return First available value.
     */
    private String getFirstAvailableValue(List<String> values) {
        for (String currentValue : values) {
            if (String.isNotBlank(currentValue)) {
                return currentValue;
            }
        }

        return null;
    }

    /**
     * @description Parses Salesforce Id.
     * @param recordIdValue Record Id value.
     * @return Parsed Id or null.
     */
    private Id parseRecordId(String recordIdValue) {
        try {
            return String.isBlank(recordIdValue) ? null : (Id) recordIdValue.trim();
        } catch (StringException exceptionInstance) {
            return null;
        }
    }

    /**
     * @description Sets error state.
     * @param message Error message.
     */
    private void setError(String message) {
        hasError = true;
        errorMessage = message;
    }

    /**
     * @description Clears error state.
     */
    private void clearError() {
        hasError = false;
        errorMessage = null;
    }
}