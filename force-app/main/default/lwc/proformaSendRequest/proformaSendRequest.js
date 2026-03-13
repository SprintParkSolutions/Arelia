import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { deleteRecord } from 'lightning/uiRecordApi';
import { refreshApex } from '@salesforce/apex';
import sendInvoice from '@salesforce/apex/ProformaInvoiceController.sendInvoiceForApproval';
import getRelatedInvoices from '@salesforce/apex/ProformaInvoiceController.getRelatedInvoices';

const COLUMNS = [
    { label: 'Invoice Name', fieldName: 'fileName', type: 'text', wrapText: true, initialWidth: 200 },
    { label: 'Client Status', fieldName: 'clientStatus', type: 'text', initialWidth: 120 },
    { label: 'Client Comments', fieldName: 'clientComments', type: 'text', wrapText: true },
    { label: 'Manager Approved', fieldName: 'managerApproved', type: 'boolean', initialWidth: 100, cellAttributes: { alignment: 'center' } },
    { label: 'Manager Comments', fieldName: 'managerComments', type: 'text', wrapText: true }
];

export default class ProformaSendRequest extends LightningElement {
    @api recordId;
    @track invoices = [];
    @track uploadedFiles = []; 
    @track isLoading = false;
    
    wiredInvoicesResult;
    columns = COLUMNS;
    // Allow more file types
    acceptedFormats = ['.pdf', '.jpg', '.png', '.jpeg', '.xls', '.xlsx', '.csv', '.doc', '.docx', '.zip'];

    get hasUploadedFiles() {
        return this.uploadedFiles && this.uploadedFiles.length > 0;
    }

    get hasInvoices() {
        return this.invoices && this.invoices.length > 0;
    }

    @wire(getRelatedInvoices, { recordId: '$recordId' })
    wiredInvoices(result) {
        this.wiredInvoicesResult = result;
        if (result.data) {
            this.invoices = result.data;
        } else if (result.error) {
            console.error('Error fetching history:', result.error);
            this.invoices = [];
        }
    }

    handleUploadFinished(event) {
        const files = event.detail.files;
        if (files && files.length > 0) {
            
            // --- NEW ICON LOGIC ---
            const processedFiles = files.map(file => {
                // Default icon
                let icon = 'doctype:attachment'; 
                
                // Get extension
                let ext = '';
                const parts = file.name.split('.');
                if(parts.length > 1) {
                    ext = parts.pop().toLowerCase();
                }

                // Map extension to SLDS Doctype Icons
                if (ext === 'pdf') {
                    icon = 'doctype:pdf';
                } else if (['jpg', 'jpeg', 'png', 'gif'].includes(ext)) {
                    icon = 'doctype:image';
                } else if (['xls', 'xlsx', 'csv'].includes(ext)) {
                    icon = 'doctype:excel';
                } else if (['doc', 'docx'].includes(ext)) {
                    icon = 'doctype:word';
                } else if (['zip', 'rar'].includes(ext)) {
                    icon = 'doctype:zip';
                } else if (['ppt', 'pptx'].includes(ext)) {
                    icon = 'doctype:ppt';
                } else if (['txt', 'rtf'].includes(ext)) {
                    icon = 'doctype:txt';
                }

                return { 
                    ...file, 
                    iconName: icon 
                };
            });

            this.uploadedFiles = [...this.uploadedFiles, ...processedFiles];
            this.showToast('Success', `${files.length} file(s) uploaded successfully.`, 'success');
            refreshApex(this.wiredInvoicesResult);
        }
    }

    async handleDeleteFile(event) {
        const fileId = event.target.dataset.id;
        this.isLoading = true;
        try {
            await deleteRecord(fileId);
            this.uploadedFiles = this.uploadedFiles.filter(file => file.documentId !== fileId);
            this.showToast('Success', 'File removed successfully', 'success');
        } catch (error) {
            console.error('Error deleting file:', error);
            this.showToast('Error', 'Error deleting file', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async handleSendClick() {
        if (this.uploadedFiles.length === 0) {
            this.showToast('Error', 'Please upload at least one file.', 'error');
            return;
        }
        
        this.isLoading = true;

        try {
            const fileIds = this.uploadedFiles.map(file => file.documentId);
            await sendInvoice({ recordId: this.recordId, fileIds: fileIds });

            this.showToast('Success', 'Proforma Invoice sent for approval successfully!', 'success');
            
            this.uploadedFiles = []; 
            this.dispatchEvent(new CloseActionScreenEvent());
            refreshApex(this.wiredInvoicesResult);

        } catch (error) {
            const message = error.body ? error.body.message : error.message;
            this.showToast('Error', message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}