import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getMilestones from '@salesforce/apex/ProjectMilestoneController.getMilestones';

const AUTO_REFRESH_INTERVAL = 20000;

export default class ProjectMilestones extends LightningElement {
    @api recordId;
    resolvedRecordId;

    milestones = [];
    completionPercentage = 0;

    wiredResult;
    refreshIntervalId;

    @wire(CurrentPageReference)
    resolveRecordId(pageRef) {
        if (this.recordId) {
            this.resolvedRecordId = this.recordId;
        } else if (pageRef?.attributes?.recordId) {
            this.resolvedRecordId = pageRef.attributes.recordId;
        }
    }

    @wire(getMilestones, { projectId: '$resolvedRecordId' })
    wiredMilestones(result) {
        this.wiredResult = result;

        if (result.data) {
            this.completionPercentage = result.data.completionPercentage;

            this.milestones = result.data.milestones.map(mile => {
                let statusLabel = 'Pending';
                let badgeClass = 'slds-badge slds-theme_warning';

                if (mile.completed) {
                    statusLabel = 'Completed';
                    badgeClass = 'slds-badge slds-theme_success';
                } else if (
                    this.completionPercentage >
                    mile.cumulativePercentage - mile.percentage
                ) {
                    statusLabel = 'In Progress';
                    badgeClass = 'slds-badge slds-theme_info';
                }

                return {
                    ...mile,
                    statusLabel,
                    badgeClass,
                    rowClass: mile.completed ? 'payment-received' : '',
                    paymentIcon: mile.paymentReceived
                        ? 'utility:success'
                        : 'utility:dash'
                };
            });

            // ✅ Set CSS variable safely
            this.template.host.style.setProperty(
                '--progress-width',
                `${this.completionPercentage}%`
            );
        }
    }

    connectedCallback() {
        this.refreshIntervalId = setInterval(() => {
            if (this.wiredResult) {
                refreshApex(this.wiredResult);
            }
        }, AUTO_REFRESH_INTERVAL);
    }

    disconnectedCallback() {
        clearInterval(this.refreshIntervalId);
    }

    get progressLabel() {
        return `${this.completionPercentage}% Complete`;
    }

    get hasRecordId() {
        return Boolean(this.resolvedRecordId);
    }

    get progressBarClass() {
        if (this.completionPercentage >= 100) {
            return 'progress-bar progress-success';
        }
        if (this.completionPercentage >= 50) {
            return 'progress-bar progress-info';
        }
        return 'progress-bar progress-warning';
    }
}