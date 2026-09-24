import { LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";

import getBudgetReview from "@salesforce/apex/OpportunityBudgetReviewController.getBudgetReview";
import saveChildRows from "@salesforce/apex/OpportunityBudgetReviewController.saveChildRows";
import submitToClient from "@salesforce/apex/OpportunityBudgetReviewController.submitToClient";

export default class OpportunityBudgetReview extends LightningElement {
    @api recordId;

    loading = true;
    busy = false;
    isReadOnly = true;
    errorText = "";

    customerBudget = null;
    supervisorBudget = null;
    finalBudget = null;

    supervisorBudgetText = "";
    estimatedBudgetDescription = "";
    duration = "";

    architectureRows = [];
    paymentTermRows = [];

    architectureDraftValues = [];
    paymentTermDraftValues = [];

    wiredResult;
    savedDto;

    @wire(getBudgetReview, { opportunityId: "$recordId" })
    wiredBudget(result) {
        this.wiredResult = result;

        const { data, error } = result;

        if (error) {
            this.errorText = this.err(error);
            this.loading = false;
        } else if (data) {
            this.errorText = "";
            this.savedDto = data;

            // Do not overwrite edits during a background refresh.
            if (this.isReadOnly) {
                this.applyDto(data);
            }

            this.loading = false;
        } else if (data === null) {
            this.errorText =
                "Budget review could not be loaded for this record.";
            this.loading = false;
        }
    }

    get isWorking() {
        return this.loading || this.busy;
    }

    get editButtonLabel() {
        return this.isReadOnly ? "Edit" : "Cancel";
    }

    get isActionDisabled() {
        return this.isWorking || !!this.errorText || !this.savedDto;
    }

    get isSaveDisabled() {
        return this.isActionDisabled || this.isReadOnly;
    }

    get inputsDisabled() {
        return this.isReadOnly || this.isWorking;
    }

    get durationLabel() {
        return this.duration || "Not specified";
    }

    get modeLabel() {
        return this.isReadOnly ? "View mode" : "Editing";
    }

    get hasArchitectureRows() {
        return this.architectureRows.length > 0;
    }

    get hasPaymentTerms() {
        return this.paymentTermRows.length > 0;
    }

    get architectureColumns() {
        return [
            {
                label: "Design",
                fieldName: "name",
                type: "text"
            },
            {
                label: "Budget (₹)",
                fieldName: "amount",
                type: "number",
                editable: !this.inputsDisabled,
                typeAttributes: {
                    minimumFractionDigits: 2,
                    maximumFractionDigits: 2
                }
            }
        ];
    }

    get paymentTermColumns() {
        return [
            {
                label: "Term",
                fieldName: "termLabel",
                type: "text",
                editable: !this.inputsDisabled
            },
            {
                label: "%",
                fieldName: "displayPercent",
                type: "percent",
                editable: !this.inputsDisabled,
                typeAttributes: {
                    maximumFractionDigits: 2,
                    step: 0.01
                }
            },
            {
                label: "Due Date",
                fieldName: "dueDate",
                type: "date-local",
                editable: !this.inputsDisabled
            }
        ];
    }

    toggleEdit() {
        if (this.isActionDisabled) {
            return;
        }

        if (!this.isReadOnly) {
            this.applyDto(this.savedDto);
            this.clearDrafts();
        }

        this.isReadOnly = !this.isReadOnly;
    }

    onSupervisorInput(event) {
        this.supervisorBudgetText = event.target.value;
        this.supervisorBudget = this.toNumber(event.target.value);
        this.finalBudget = this.supervisorBudget;
    }

    onDescriptionInput(event) {
        this.estimatedBudgetDescription = event.target.value;
    }

    onDurationInput(event) {
        this.duration = event.target.value;
    }

    onArchChange(event) {
        this.architectureDraftValues = this.combineDrafts(
            this.architectureDraftValues,
            event.detail.draftValues
        );
    }

    onTermChange(event) {
        this.paymentTermDraftValues = this.combineDrafts(
            this.paymentTermDraftValues,
            event.detail.draftValues
        );
    }

    validateInputs() {
        return [
            ...this.template.querySelectorAll(
                "lightning-input, lightning-textarea"
            )
        ].reduce(
            (valid, input) => input.reportValidity() && valid,
            true
        );
    }

    buildRequest() {
        const rows = this.mergeDrafts(
            this.architectureRows,
            this.architectureDraftValues
        );

        const terms = this.mergeDrafts(
            this.paymentTermRows,
            this.paymentTermDraftValues
        );

        return {
            inputCustomerBudget: this.customerBudget,
            inputSupervisorBudget: this.supervisorBudget,
            inputDuration: this.duration,

            inputEstimatedBudgetDescription:
                this.estimatedBudgetDescription || null,

            // Allows the field to be cleared intentionally.
            updateEstimatedBudgetDescription: true,

            architectureRows: rows.map((row) => ({
                id: row.id,
                amount: this.toNumber(row.amount)
            })),

            paymentTerms: terms.map((term) => ({
                id: term.id,
                termLabel: term.termLabel,
                percentage:
                    term.displayPercent == null ||
                    term.displayPercent === ""
                        ? null
                        : this.toNumber(term.displayPercent) * 100,
                dueDate: term.dueDate,
                paymentReceived: term.paymentReceived
            }))
        };
    }

    async persistChanges() {
        const dto = await saveChildRows({
            opportunityId: this.recordId,
            req: this.buildRequest()
        });

        if (!dto) {
            throw new Error(
                "No saved budget was returned. Refresh the record and try again."
            );
        }

        this.savedDto = dto;
        this.applyDto(dto);
        this.isReadOnly = true;
        this.clearDrafts();
    }

    async refreshSavedData() {
        try {
            await Promise.all([
                notifyRecordUpdateAvailable([
                    { recordId: this.recordId }
                ]),
                refreshApex(this.wiredResult)
            ]);
        } catch (error) {
            this.toast(
                "Refresh needed",
                "Your changes were saved, but the page could not refresh. Reload the record.",
                "warning"
            );
        }
    }

    async save() {
        if (this.isSaveDisabled || !this.validateInputs()) {
            return false;
        }

        this.busy = true;

        try {
            await this.persistChanges();
            await this.refreshSavedData();

            this.toast(
                "Success",
                "Budget updated successfully.",
                "success"
            );

            return true;
        } catch (error) {
            this.toast(
                "Unable to save",
                this.err(error),
                "error"
            );

            return false;
        } finally {
            this.busy = false;
        }
    }

    async handleSendToClient() {
        if (
            this.isActionDisabled ||
            (!this.isReadOnly && !this.validateInputs())
        ) {
            return;
        }

        this.busy = true;
        let saved = false;

        try {
            if (!this.isReadOnly) {
                await this.persistChanges();
                saved = true;
            }

            await submitToClient({
                recordId: this.recordId
            });

            await this.refreshSavedData();

            this.toast(
                "Success",
                "Budget sent for Client Approval.",
                "success"
            );
        } catch (error) {
            this.toast(
                "Unable to submit",
                (saved
                    ? "Budget saved, but submission failed. "
                    : "") + this.err(error),
                "error"
            );

            if (saved) {
                await this.refreshSavedData();
            }
        } finally {
            this.busy = false;
        }
    }

    applyDto(dto) {
        if (!dto) {
            return;
        }

        this.customerBudget = dto.customerBudget ?? null;
        this.supervisorBudget = dto.supervisorBudget ?? null;
        this.finalBudget = dto.finalBudget ?? null;

        this.supervisorBudgetText =
            this.supervisorBudget == null
                ? ""
                : String(this.supervisorBudget);

        this.estimatedBudgetDescription =
            dto.estimatedBudgetDescription ?? "";

        this.duration = dto.estimatedDuration ?? "";

        this.architectureRows = (dto.architectureRows || []).map(
            (row) => ({ ...row })
        );

        this.paymentTermRows = (dto.paymentTerms || []).map(
            (term) => ({
                ...term,
                displayPercent:
                    term.percentage == null
                        ? null
                        : Number(term.percentage) / 100
            })
        );
    }

    clearDrafts() {
        this.architectureDraftValues = [];
        this.paymentTermDraftValues = [];
    }

    toNumber(value) {
        if (value == null || String(value).trim() === "") {
            return null;
        }

        const number = Number(
            String(value).replace(/,/g, "").trim()
        );

        if (!Number.isFinite(number)) {
            throw new Error(
                "Enter a valid budget or percentage."
            );
        }

        return number;
    }

    combineDrafts(existing, incoming) {
        const map = new Map(
            existing.map((row) => [row.id, { ...row }])
        );

        (incoming || []).forEach((row) => {
            map.set(row.id, {
                ...map.get(row.id),
                ...row
            });
        });

        return Array.from(map.values());
    }

    mergeDrafts(base, drafts) {
        const map = new Map(
            base.map((row) => [row.id, { ...row }])
        );

        drafts.forEach((row) => {
            if (map.has(row.id)) {
                map.set(row.id, {
                    ...map.get(row.id),
                    ...row
                });
            }
        });

        return Array.from(map.values());
    }

    toast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    err(error) {
        if (Array.isArray(error?.body)) {
            return error.body
                .map((item) => item.message)
                .join("; ");
        }

        return (
            error?.body?.message ||
            error?.message ||
            "Unknown error"
        );
    }
}