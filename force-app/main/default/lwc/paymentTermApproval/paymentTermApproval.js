import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getApprovalData from '@salesforce/apex/PaymentTermController.getApprovalData';
import submitDecision from '@salesforce/apex/PaymentTermController.submitDecision';
import ARELIA_SITE_LABEL from '@salesforce/label/c.Arelia_Site_Label';

// Import Standard Modules for Popups
import LightningAlert from 'lightning/alert';
import LightningConfirm from 'lightning/confirm';

export default class PaymentTermApproval extends LightningElement {
    @track approvalData;
    @track terms = [];
    @track comments = '';
    @track isLoading = true;
    @track error;
    
    // UI State
    @track showCommentBox = false;
    @track isProcessed = false;
    
    // Success Modal State only (Confirmation is now handled by JS)
    @track showSuccessModal = false;
    
    recordId;
    userType; 

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.recordId = currentPageReference.state.id;
            this.userType = currentPageReference.state.type || 'Manager';
            this.loadData();
        }
    }

    loadData() {
        if (!this.recordId) {
            this.error = 'Invalid Link: Record ID missing.';
            this.isLoading = false;
            return;
        }

        getApprovalData({ recordId: this.recordId })
            .then(result => {
                this.approvalData = result;
                this.terms = result.terms.map((t, i) => ({
                    ...t,
                    serialNumber: i + 1,
                    Term_Label__c: t.Term_Label__c || t.Name
                }));
                
                this.isLoading = false;
                
                const status = result.opportunity.Payment_Terms_Status__c;
                if ((this.userType === 'Manager' && status !== 'Sent for Manager Approval') ||
                    (this.userType === 'Client' && status !== 'Sent for Client Approval')) {
                     this.isProcessed = true;
                }
            })
            .catch(err => {
                console.error(err);
                this.error = 'Error loading data. The record may be invalid.';
                this.isLoading = false;
            });
    }

    handleCommentChange(e) { 
        this.comments = e.target.value; 
    }

    // --- BUTTON CLICKS ---

    async handleApproveClick() {
        // 1. Clear any rejection data if they switch back to Approve
        this.comments = '';
        this.showCommentBox = false;

        // 2. Open Standard Confirmation Dialog
        const result = await LightningConfirm.open({
            message: 'Are you sure you want to APPROVE these payment terms? This action cannot be undone.',
            variant: 'header',
            label: 'Confirm Approval',
            theme: 'success', // Green header
        });

        // 3. If User clicked "OK", proceed
        if (result) {
            this.submit('Approve');
        }
    }

    handleRequestChangesClick() {
        // Toggle the comment box view
        this.showCommentBox = !this.showCommentBox;
    }

    async handleRejectClick() {
        // 1. Validate Comments
        if (!this.comments || this.comments.trim() === '') {
            await LightningAlert.open({
                message: 'Please enter remarks before submitting a rejection.',
                theme: 'error',
                label: 'Validation Error',
            });
            return;
        }

        // 2. Open Standard Confirmation Dialog
        const result = await LightningConfirm.open({
            message: 'Are you sure you want to REQUEST CHANGES? The remarks will be sent to the team.',
            variant: 'header',
            label: 'Confirm Rejection',
            theme: 'warning', // Orange header
        });

        // 3. If User clicked "OK", proceed
        if (result) {
            this.submit('Reject');
        }
    }

    // --- SUBMISSION ---

    // --- Update only the submit method in paymentTermApproval.js ---
submit(action) {
    this.isLoading = true;

    // FIX: Wrap parameters into an object named 'data' 
    // to match the DecisionInput wrapper in Apex
    const decisionData = {
        userType: this.userType,
        action: action,
        comments: this.comments
    };

    submitDecision({ 
        recordId: this.recordId, 
        data: decisionData // This matches the @AuraEnabled parameter name
    })
    .then(() => {
        this.isLoading = false;
        this.showSuccessModal = true;
    })
    .catch(err => {
        console.error('Error:', err);
        this.isLoading = false;
        this.error = err.body ? err.body.message : err.message;
    });
}

    // --- NAVIGATION ---

    handleNavigateHome() {
        this.isLoading = true; 
        window.location.href = ARELIA_SITE_LABEL;
    }
}