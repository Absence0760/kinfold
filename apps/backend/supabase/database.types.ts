export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      allocation_preferences: {
        Row: {
          member_id: string
          target: Database["public"]["Enums"]["allocation_target"]
          weight_pct: number
        }
        Insert: {
          member_id: string
          target: Database["public"]["Enums"]["allocation_target"]
          weight_pct: number
        }
        Update: {
          member_id?: string
          target?: Database["public"]["Enums"]["allocation_target"]
          weight_pct?: number
        }
        Relationships: [
          {
            foreignKeyName: "allocation_preferences_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
        ]
      }
      appeals: {
        Row: {
          created_at: string
          decided_at: string | null
          decided_by: string | null
          id: string
          member_id: string
          reason: string
          request_id: string
          status: Database["public"]["Enums"]["appeal_status"]
        }
        Insert: {
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          id?: string
          member_id: string
          reason: string
          request_id: string
          status?: Database["public"]["Enums"]["appeal_status"]
        }
        Update: {
          created_at?: string
          decided_at?: string | null
          decided_by?: string | null
          id?: string
          member_id?: string
          reason?: string
          request_id?: string
          status?: Database["public"]["Enums"]["appeal_status"]
        }
        Relationships: [
          {
            foreignKeyName: "appeals_decided_by_fkey"
            columns: ["decided_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "appeals_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "appeals_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "board_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "appeals_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
        ]
      }
      contributions: {
        Row: {
          amount_cents: number
          contributor_id: string | null
          created_at: string
          id: string
          loan_id: string | null
          partner_ref: string | null
          pool_allocation_id: string | null
          refund_partner_ref: string | null
          refunded_at: string | null
          refunded_cents: number | null
          request_id: string
          source: Database["public"]["Enums"]["contribution_source"]
          status: Database["public"]["Enums"]["contribution_status"]
        }
        Insert: {
          amount_cents: number
          contributor_id?: string | null
          created_at?: string
          id?: string
          loan_id?: string | null
          partner_ref?: string | null
          pool_allocation_id?: string | null
          refund_partner_ref?: string | null
          refunded_at?: string | null
          refunded_cents?: number | null
          request_id: string
          source: Database["public"]["Enums"]["contribution_source"]
          status?: Database["public"]["Enums"]["contribution_status"]
        }
        Update: {
          amount_cents?: number
          contributor_id?: string | null
          created_at?: string
          id?: string
          loan_id?: string | null
          partner_ref?: string | null
          pool_allocation_id?: string | null
          refund_partner_ref?: string | null
          refunded_at?: string | null
          refunded_cents?: number | null
          request_id?: string
          source?: Database["public"]["Enums"]["contribution_source"]
          status?: Database["public"]["Enums"]["contribution_status"]
        }
        Relationships: [
          {
            foreignKeyName: "contributions_contributor_id_fkey"
            columns: ["contributor_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contributions_loan_id_fkey"
            columns: ["loan_id"]
            isOneToOne: false
            referencedRelation: "family_loans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contributions_pool_allocation_id_fkey"
            columns: ["pool_allocation_id"]
            isOneToOne: false
            referencedRelation: "pool_allocations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contributions_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "board_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contributions_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
        ]
      }
      covered_assets: {
        Row: {
          description: string
          id: string
          kind: Database["public"]["Enums"]["asset_kind"]
          member_id: string
          registered_on: string
          removed_on: string | null
          value_cents: number
          verified_at: string | null
        }
        Insert: {
          description: string
          id?: string
          kind: Database["public"]["Enums"]["asset_kind"]
          member_id: string
          registered_on?: string
          removed_on?: string | null
          value_cents: number
          verified_at?: string | null
        }
        Update: {
          description?: string
          id?: string
          kind?: Database["public"]["Enums"]["asset_kind"]
          member_id?: string
          registered_on?: string
          removed_on?: string | null
          value_cents?: number
          verified_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "covered_assets_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
        ]
      }
      evidence: {
        Row: {
          captured_in_app: boolean
          content_credentials: Json | null
          created_at: string
          id: string
          kind: Database["public"]["Enums"]["evidence_kind"]
          original_path: string
          perceptual_hash: string | null
          redacted_path: string | null
          redaction_status: Database["public"]["Enums"]["redaction_status"]
          request_id: string
          sha256: string
        }
        Insert: {
          captured_in_app?: boolean
          content_credentials?: Json | null
          created_at?: string
          id?: string
          kind: Database["public"]["Enums"]["evidence_kind"]
          original_path: string
          perceptual_hash?: string | null
          redacted_path?: string | null
          redaction_status?: Database["public"]["Enums"]["redaction_status"]
          request_id: string
          sha256: string
        }
        Update: {
          captured_in_app?: boolean
          content_credentials?: Json | null
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["evidence_kind"]
          original_path?: string
          perceptual_hash?: string | null
          redacted_path?: string | null
          redaction_status?: Database["public"]["Enums"]["redaction_status"]
          request_id?: string
          sha256?: string
        }
        Relationships: [
          {
            foreignKeyName: "evidence_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "board_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "evidence_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
        ]
      }
      family_loans: {
        Row: {
          agreement_path: string | null
          borrower_id: string
          borrower_signed_at: string | null
          created_at: string
          default_plan: Database["public"]["Enums"]["default_plan"]
          defaulted_at: string | null
          id: string
          imputed_rate_bps: number | null
          lender_id: string
          lender_signed_at: string | null
          lien_recorded_at: string | null
          pause_months_per_year: number
          payment_day: number
          principal_cents: number
          request_id: string | null
          secured: boolean
          status: Database["public"]["Enums"]["loan_status"]
        }
        Insert: {
          agreement_path?: string | null
          borrower_id: string
          borrower_signed_at?: string | null
          created_at?: string
          default_plan?: Database["public"]["Enums"]["default_plan"]
          defaulted_at?: string | null
          id?: string
          imputed_rate_bps?: number | null
          lender_id: string
          lender_signed_at?: string | null
          lien_recorded_at?: string | null
          pause_months_per_year?: number
          payment_day?: number
          principal_cents: number
          request_id?: string | null
          secured?: boolean
          status?: Database["public"]["Enums"]["loan_status"]
        }
        Update: {
          agreement_path?: string | null
          borrower_id?: string
          borrower_signed_at?: string | null
          created_at?: string
          default_plan?: Database["public"]["Enums"]["default_plan"]
          defaulted_at?: string | null
          id?: string
          imputed_rate_bps?: number | null
          lender_id?: string
          lender_signed_at?: string | null
          lien_recorded_at?: string | null
          pause_months_per_year?: number
          payment_day?: number
          principal_cents?: number
          request_id?: string | null
          secured?: boolean
          status?: Database["public"]["Enums"]["loan_status"]
        }
        Relationships: [
          {
            foreignKeyName: "family_loans_borrower_id_fkey"
            columns: ["borrower_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "family_loans_lender_id_fkey"
            columns: ["lender_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "family_loans_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "board_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "family_loans_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
        ]
      }
      fund_settings: {
        Row: {
          band_size: number
          fund: Database["public"]["Enums"]["fund"]
          kinds: Database["public"]["Enums"]["request_kind"][]
          max_request_cents: number
          min_score: number
          reserve_bps: number
          updated_at: string
          waiting_days: number
        }
        Insert: {
          band_size: number
          fund: Database["public"]["Enums"]["fund"]
          kinds: Database["public"]["Enums"]["request_kind"][]
          max_request_cents: number
          min_score: number
          reserve_bps: number
          updated_at?: string
          waiting_days: number
        }
        Update: {
          band_size?: number
          fund?: Database["public"]["Enums"]["fund"]
          kinds?: Database["public"]["Enums"]["request_kind"][]
          max_request_cents?: number
          min_score?: number
          reserve_bps?: number
          updated_at?: string
          waiting_days?: number
        }
        Relationships: []
      }
      income_verifications: {
        Row: {
          expires_at: string
          id: string
          member_id: string
          method: Database["public"]["Enums"]["income_method"]
          monthly_income_cents: number
          provider_ref: string | null
          verified_at: string
        }
        Insert: {
          expires_at?: string
          id?: string
          member_id: string
          method: Database["public"]["Enums"]["income_method"]
          monthly_income_cents: number
          provider_ref?: string | null
          verified_at?: string
        }
        Update: {
          expires_at?: string
          id?: string
          member_id?: string
          method?: Database["public"]["Enums"]["income_method"]
          monthly_income_cents?: number
          provider_ref?: string | null
          verified_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "income_verifications_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
        ]
      }
      loan_forgiveness: {
        Row: {
          amount_cents: number
          created_at: string
          id: string
          loan_id: string
          tax_year: number
        }
        Insert: {
          amount_cents: number
          created_at?: string
          id?: string
          loan_id: string
          tax_year: number
        }
        Update: {
          amount_cents?: number
          created_at?: string
          id?: string
          loan_id?: string
          tax_year?: number
        }
        Relationships: [
          {
            foreignKeyName: "loan_forgiveness_loan_id_fkey"
            columns: ["loan_id"]
            isOneToOne: false
            referencedRelation: "family_loans"
            referencedColumns: ["id"]
          },
        ]
      }
      loan_installments: {
        Row: {
          amount_cents: number
          due_on: string
          loan_id: string
          paid_cents: number
          paused: boolean
          seq: number
        }
        Insert: {
          amount_cents: number
          due_on: string
          loan_id: string
          paid_cents?: number
          paused?: boolean
          seq: number
        }
        Update: {
          amount_cents?: number
          due_on?: string
          loan_id?: string
          paid_cents?: number
          paused?: boolean
          seq?: number
        }
        Relationships: [
          {
            foreignKeyName: "loan_installments_loan_id_fkey"
            columns: ["loan_id"]
            isOneToOne: false
            referencedRelation: "family_loans"
            referencedColumns: ["id"]
          },
        ]
      }
      loan_pauses: {
        Row: {
          created_by: string
          id: string
          loan_id: string
          months: number
          reason: string | null
          started_on: string
        }
        Insert: {
          created_by: string
          id?: string
          loan_id: string
          months: number
          reason?: string | null
          started_on?: string
        }
        Update: {
          created_by?: string
          id?: string
          loan_id?: string
          months?: number
          reason?: string | null
          started_on?: string
        }
        Relationships: [
          {
            foreignKeyName: "loan_pauses_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "loan_pauses_loan_id_fkey"
            columns: ["loan_id"]
            isOneToOne: false
            referencedRelation: "family_loans"
            referencedColumns: ["id"]
          },
        ]
      }
      member_roles: {
        Row: {
          granted_at: string
          member_id: string
          role: Database["public"]["Enums"]["member_role"]
        }
        Insert: {
          granted_at?: string
          member_id: string
          role: Database["public"]["Enums"]["member_role"]
        }
        Update: {
          granted_at?: string
          member_id?: string
          role?: Database["public"]["Enums"]["member_role"]
        }
        Relationships: [
          {
            foreignKeyName: "member_roles_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
        ]
      }
      members: {
        Row: {
          display_name: string
          id: string
          joined_at: string
          region: string
          status: Database["public"]["Enums"]["member_status"]
        }
        Insert: {
          display_name: string
          id: string
          joined_at?: string
          region: string
          status?: Database["public"]["Enums"]["member_status"]
        }
        Update: {
          display_name?: string
          id?: string
          joined_at?: string
          region?: string
          status?: Database["public"]["Enums"]["member_status"]
        }
        Relationships: []
      }
      open_books: {
        Row: {
          allocated_cents: number | null
          fund: Database["public"]["Enums"]["fund"]
          month: string
          paid_out_cents: number | null
          pool_runs: number
          pool_runs_short: number | null
          published_at: string
          requests_paid: number | null
          reserve_cents: number | null
        }
        Insert: {
          allocated_cents?: number | null
          fund: Database["public"]["Enums"]["fund"]
          month: string
          paid_out_cents?: number | null
          pool_runs: number
          pool_runs_short?: number | null
          published_at?: string
          requests_paid?: number | null
          reserve_cents?: number | null
        }
        Update: {
          allocated_cents?: number | null
          fund?: Database["public"]["Enums"]["fund"]
          month?: string
          paid_out_cents?: number | null
          pool_runs?: number
          pool_runs_short?: number | null
          published_at?: string
          requests_paid?: number | null
          reserve_cents?: number | null
        }
        Relationships: []
      }
      payees: {
        Row: {
          created_at: string
          id: string
          kind: Database["public"]["Enums"]["payee_kind"]
          legal_name: string
          partner_account_ref: string | null
          proposed_by: string | null
          region: string
          status: Database["public"]["Enums"]["verification_status"]
          verified_at: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          kind: Database["public"]["Enums"]["payee_kind"]
          legal_name: string
          partner_account_ref?: string | null
          proposed_by?: string | null
          region: string
          status?: Database["public"]["Enums"]["verification_status"]
          verified_at?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          kind?: Database["public"]["Enums"]["payee_kind"]
          legal_name?: string
          partner_account_ref?: string | null
          proposed_by?: string | null
          region?: string
          status?: Database["public"]["Enums"]["verification_status"]
          verified_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "payees_proposed_by_fkey"
            columns: ["proposed_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
        ]
      }
      payouts: {
        Row: {
          amount_cents: number
          created_at: string
          id: string
          invoice_evidence_id: string
          partner_ref: string | null
          payee_id: string
          request_id: string
          sent_at: string | null
          status: Database["public"]["Enums"]["payout_status"]
        }
        Insert: {
          amount_cents: number
          created_at?: string
          id?: string
          invoice_evidence_id: string
          partner_ref?: string | null
          payee_id: string
          request_id: string
          sent_at?: string | null
          status?: Database["public"]["Enums"]["payout_status"]
        }
        Update: {
          amount_cents?: number
          created_at?: string
          id?: string
          invoice_evidence_id?: string
          partner_ref?: string | null
          payee_id?: string
          request_id?: string
          sent_at?: string | null
          status?: Database["public"]["Enums"]["payout_status"]
        }
        Relationships: [
          {
            foreignKeyName: "payouts_invoice_evidence_id_fkey"
            columns: ["invoice_evidence_id"]
            isOneToOne: false
            referencedRelation: "evidence"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payouts_payee_id_fkey"
            columns: ["payee_id"]
            isOneToOne: false
            referencedRelation: "payees"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payouts_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "board_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payouts_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
        ]
      }
      pool_allocations: {
        Row: {
          band: number
          grant_cents: number
          id: string
          need_cents: number
          request_id: string
          run_id: string
          score: number
        }
        Insert: {
          band: number
          grant_cents: number
          id?: string
          need_cents: number
          request_id: string
          run_id: string
          score: number
        }
        Update: {
          band?: number
          grant_cents?: number
          id?: string
          need_cents?: number
          request_id?: string
          run_id?: string
          score?: number
        }
        Relationships: [
          {
            foreignKeyName: "pool_allocations_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "board_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pool_allocations_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pool_allocations_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "pool_runs"
            referencedColumns: ["id"]
          },
        ]
      }
      pool_runs: {
        Row: {
          algorithm_version: string
          allocated_cents: number
          available_cents: number
          fund: Database["public"]["Enums"]["fund"]
          id: string
          reserve_cents: number
          run_at: string
          settings: Json
        }
        Insert: {
          algorithm_version: string
          allocated_cents?: number
          available_cents: number
          fund: Database["public"]["Enums"]["fund"]
          id?: string
          reserve_cents: number
          run_at?: string
          settings: Json
        }
        Update: {
          algorithm_version?: string
          allocated_cents?: number
          available_cents?: number
          fund?: Database["public"]["Enums"]["fund"]
          id?: string
          reserve_cents?: number
          run_at?: string
          settings?: Json
        }
        Relationships: []
      }
      request_events: {
        Row: {
          actor: string | null
          at: string
          from_status: Database["public"]["Enums"]["request_status"] | null
          id: number
          request_id: string
          to_status: Database["public"]["Enums"]["request_status"]
        }
        Insert: {
          actor?: string | null
          at?: string
          from_status?: Database["public"]["Enums"]["request_status"] | null
          id?: never
          request_id: string
          to_status: Database["public"]["Enums"]["request_status"]
        }
        Update: {
          actor?: string | null
          at?: string
          from_status?: Database["public"]["Enums"]["request_status"] | null
          id?: never
          request_id?: string
          to_status?: Database["public"]["Enums"]["request_status"]
        }
        Relationships: [
          {
            foreignKeyName: "request_events_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "board_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "request_events_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
        ]
      }
      request_invites: {
        Row: {
          accepted_at: string | null
          accepted_by: string | null
          created_at: string
          expires_at: string
          id: string
          relationship: string
          request_id: string
          token_sha256: string
        }
        Insert: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          relationship: string
          request_id: string
          token_sha256: string
        }
        Update: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          relationship?: string
          request_id?: string
          token_sha256?: string
        }
        Relationships: [
          {
            foreignKeyName: "request_invites_accepted_by_fkey"
            columns: ["accepted_by"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "request_invites_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "board_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "request_invites_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
        ]
      }
      request_supporters: {
        Row: {
          joined_at: string
          member_id: string
          relationship: string
          request_id: string
        }
        Insert: {
          joined_at?: string
          member_id: string
          relationship: string
          request_id: string
        }
        Update: {
          joined_at?: string
          member_id?: string
          relationship?: string
          request_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "request_supporters_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "request_supporters_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "board_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "request_supporters_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
        ]
      }
      request_transitions: {
        Row: {
          from_status: Database["public"]["Enums"]["request_status"]
          to_status: Database["public"]["Enums"]["request_status"]
        }
        Insert: {
          from_status: Database["public"]["Enums"]["request_status"]
          to_status: Database["public"]["Enums"]["request_status"]
        }
        Update: {
          from_status?: Database["public"]["Enums"]["request_status"]
          to_status?: Database["public"]["Enums"]["request_status"]
        }
        Relationships: []
      }
      requests: {
        Row: {
          amount_cents: number
          asset_id: string | null
          created_at: string
          current_score: number | null
          description: string
          funding: Database["public"]["Enums"]["funding_mode"]
          id: string
          incident_on: string
          kind: Database["public"]["Enums"]["request_kind"]
          member_id: string
          payee_id: string | null
          public_summary: string | null
          public_summary_confirmed_at: string | null
          status: Database["public"]["Enums"]["request_status"]
          submitted_at: string | null
          title: string
        }
        Insert: {
          amount_cents: number
          asset_id?: string | null
          created_at?: string
          current_score?: number | null
          description?: string
          funding?: Database["public"]["Enums"]["funding_mode"]
          id?: string
          incident_on: string
          kind: Database["public"]["Enums"]["request_kind"]
          member_id: string
          payee_id?: string | null
          public_summary?: string | null
          public_summary_confirmed_at?: string | null
          status?: Database["public"]["Enums"]["request_status"]
          submitted_at?: string | null
          title: string
        }
        Update: {
          amount_cents?: number
          asset_id?: string | null
          created_at?: string
          current_score?: number | null
          description?: string
          funding?: Database["public"]["Enums"]["funding_mode"]
          id?: string
          incident_on?: string
          kind?: Database["public"]["Enums"]["request_kind"]
          member_id?: string
          payee_id?: string | null
          public_summary?: string | null
          public_summary_confirmed_at?: string | null
          status?: Database["public"]["Enums"]["request_status"]
          submitted_at?: string | null
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "requests_asset_id_fkey"
            columns: ["asset_id"]
            isOneToOne: false
            referencedRelation: "covered_assets"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "requests_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "requests_payee_id_fkey"
            columns: ["payee_id"]
            isOneToOne: false
            referencedRelation: "payees"
            referencedColumns: ["id"]
          },
        ]
      }
      reviews: {
        Row: {
          created_at: string
          decision: Database["public"]["Enums"]["review_decision"]
          id: string
          reason: string
          request_id: string
          reviewer_id: string
        }
        Insert: {
          created_at?: string
          decision: Database["public"]["Enums"]["review_decision"]
          id?: string
          reason: string
          request_id: string
          reviewer_id: string
        }
        Update: {
          created_at?: string
          decision?: Database["public"]["Enums"]["review_decision"]
          id?: string
          reason?: string
          request_id?: string
          reviewer_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "reviews_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "board_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reviews_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reviews_reviewer_id_fkey"
            columns: ["reviewer_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
        ]
      }
      scores: {
        Row: {
          created_at: string
          id: string
          inputs_sha256: string
          model: string
          model_version: string
          prompt_version: string
          reasons: Json
          request_id: string
          score: number
        }
        Insert: {
          created_at?: string
          id?: string
          inputs_sha256: string
          model: string
          model_version: string
          prompt_version: string
          reasons: Json
          request_id: string
          score: number
        }
        Update: {
          created_at?: string
          id?: string
          inputs_sha256?: string
          model?: string
          model_version?: string
          prompt_version?: string
          reasons?: Json
          request_id?: string
          score?: number
        }
        Relationships: [
          {
            foreignKeyName: "scores_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "board_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scores_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
        ]
      }
      subscription_formulas: {
        Row: {
          cap_cents: number
          core_share_bps: number
          effective_from: string
          floor_income_cents: number
          rate_bps: number
          version: number
        }
        Insert: {
          cap_cents: number
          core_share_bps: number
          effective_from: string
          floor_income_cents: number
          rate_bps: number
          version: number
        }
        Update: {
          cap_cents?: number
          core_share_bps?: number
          effective_from?: string
          floor_income_cents?: number
          rate_bps?: number
          version?: number
        }
        Relationships: []
      }
      subscription_payments: {
        Row: {
          amount_cents: number
          captured_at: string | null
          id: string
          member_id: string
          partner_ref: string | null
          period: string
          status: Database["public"]["Enums"]["payment_status"]
          subscription_id: string
        }
        Insert: {
          amount_cents: number
          captured_at?: string | null
          id?: string
          member_id: string
          partner_ref?: string | null
          period: string
          status?: Database["public"]["Enums"]["payment_status"]
          subscription_id: string
        }
        Update: {
          amount_cents?: number
          captured_at?: string | null
          id?: string
          member_id?: string
          partner_ref?: string | null
          period?: string
          status?: Database["public"]["Enums"]["payment_status"]
          subscription_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "subscription_payments_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "subscription_payments_subscription_id_fkey"
            columns: ["subscription_id"]
            isOneToOne: false
            referencedRelation: "subscriptions"
            referencedColumns: ["id"]
          },
        ]
      }
      subscriptions: {
        Row: {
          ends_on: string | null
          formula_version: number
          id: string
          income_verification_id: string
          member_id: string
          monthly_cents: number
          starts_on: string
        }
        Insert: {
          ends_on?: string | null
          formula_version: number
          id?: string
          income_verification_id: string
          member_id: string
          monthly_cents: number
          starts_on?: string
        }
        Update: {
          ends_on?: string | null
          formula_version?: number
          id?: string
          income_verification_id?: string
          member_id?: string
          monthly_cents?: number
          starts_on?: string
        }
        Relationships: [
          {
            foreignKeyName: "subscriptions_formula_version_fkey"
            columns: ["formula_version"]
            isOneToOne: false
            referencedRelation: "subscription_formulas"
            referencedColumns: ["version"]
          },
          {
            foreignKeyName: "subscriptions_income_verification_id_fkey"
            columns: ["income_verification_id"]
            isOneToOne: false
            referencedRelation: "income_verifications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "subscriptions_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      board_requests: {
        Row: {
          amount_band_max_cents: number | null
          amount_band_min_cents: number | null
          amount_cents: number | null
          area: string | null
          id: string | null
          kind: Database["public"]["Enums"]["request_kind"] | null
          month_of: string | null
          public_summary: string | null
          score_band: number | null
          status: Database["public"]["Enums"]["request_status"] | null
        }
        Relationships: []
      }
      loan_missed_installments: {
        Row: {
          due_on: string | null
          loan_id: string | null
          owed_cents: number | null
          seq: number | null
        }
        Relationships: [
          {
            foreignKeyName: "loan_installments_loan_id_fkey"
            columns: ["loan_id"]
            isOneToOne: false
            referencedRelation: "family_loans"
            referencedColumns: ["id"]
          },
        ]
      }
      refunds_due: {
        Row: {
          amount_cents: number | null
          contribution_id: string | null
          contributor_id: string | null
          created_at: string | null
          loan_id: string | null
          partner_ref: string | null
          pool_allocation_id: string | null
          refund_cents: number | null
          request_id: string | null
          request_status: Database["public"]["Enums"]["request_status"] | null
          source: Database["public"]["Enums"]["contribution_source"] | null
        }
        Relationships: [
          {
            foreignKeyName: "contributions_contributor_id_fkey"
            columns: ["contributor_id"]
            isOneToOne: false
            referencedRelation: "members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contributions_loan_id_fkey"
            columns: ["loan_id"]
            isOneToOne: false
            referencedRelation: "family_loans"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contributions_pool_allocation_id_fkey"
            columns: ["pool_allocation_id"]
            isOneToOne: false
            referencedRelation: "pool_allocations"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contributions_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "board_requests"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contributions_request_id_fkey"
            columns: ["request_id"]
            isOneToOne: false
            referencedRelation: "requests"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      accept_invite: { Args: { p_token: string }; Returns: string }
      apply_default_plan: {
        Args: { p_loan: string }
        Returns: Database["public"]["Enums"]["loan_status"]
      }
      board_area: { Args: { p_region: string }; Returns: string }
      capture_contributions: { Args: { p_request: string }; Returns: number }
      close_account: { Args: never; Returns: undefined }
      confirm_public_summary: {
        Args: { p_request: string }
        Returns: undefined
      }
      confirm_redaction: { Args: { p_evidence: string }; Returns: undefined }
      coverage_started_on: { Args: { p_member: string }; Returns: string }
      create_invite: {
        Args: { p_relationship: string; p_request: string }
        Returns: string
      }
      decide_appeal: {
        Args: { p_appeal: string; p_uphold: boolean }
        Returns: undefined
      }
      file_appeal: {
        Args: { p_reason: string; p_request: string }
        Returns: string
      }
      forgive_loan: {
        Args: { p_amount_cents: number; p_loan: string; p_tax_year: number }
        Returns: undefined
      }
      fund_for_kind: {
        Args: { p_kind: Database["public"]["Enums"]["request_kind"] }
        Returns: Database["public"]["Enums"]["fund"]
      }
      has_role: {
        Args: { p_role: Database["public"]["Enums"]["member_role"] }
        Returns: boolean
      }
      is_active_member: { Args: never; Returns: boolean }
      is_supporter: { Args: { p_request: string }; Returns: boolean }
      loan_outstanding_cents: { Args: { p_loan: string }; Returns: number }
      mark_refunded: {
        Args: { p_contribution: string; p_partner_ref: string }
        Returns: undefined
      }
      my_giving_record: {
        Args: never
        Returns: {
          gifts_given_cents: number
          lent_cents: number
          received_from_people_cents: number
          received_from_pool_cents: number
          requests_paid: number
          subscriptions_paid_cents: number
        }[]
      }
      my_reliability: {
        Args: never
        Returns: {
          installments_due: number
          installments_paid_on_time: number
          member_since: string
          requests_paid: number
          subscription_payments: number
        }[]
      }
      my_request_reviews: {
        Args: { p_request: string }
        Returns: {
          created_at: string
          decision: Database["public"]["Enums"]["review_decision"]
          reason: string
        }[]
      }
      on_board: {
        Args: { r: Database["public"]["Tables"]["requests"]["Row"] }
        Returns: boolean
      }
      pause_loan: {
        Args: { p_loan: string; p_months: number; p_reason?: string }
        Returns: undefined
      }
      pledge: {
        Args: {
          p_amount_cents: number
          p_request: string
          p_source: Database["public"]["Enums"]["contribution_source"]
        }
        Returns: string
      }
      pool_requests_paid_3y: { Args: { p_member: string }; Returns: number }
      post_journal: {
        Args: {
          p_fund: Database["public"]["Enums"]["fund"]
          p_kind: string
          p_lines: Json
          p_partner_ref: string
          p_ref: string
        }
        Returns: string
      }
      publish_open_books: { Args: { p_month: string }; Returns: undefined }
      record_fraud_signal: {
        Args: {
          p_detail?: Json
          p_kind: string
          p_request: string
          p_severity: string
        }
        Returns: number
      }
      record_identity_check: {
        Args: { p_member: string; p_provider: string; p_provider_ref: string }
        Returns: undefined
      }
      record_review: {
        Args: {
          p_decision: Database["public"]["Enums"]["review_decision"]
          p_reason: string
          p_request: string
        }
        Returns: Database["public"]["Enums"]["request_status"]
      }
      record_score: {
        Args: {
          p_inputs_sha256: string
          p_model: string
          p_model_version: string
          p_prompt_version: string
          p_reasons: Json
          p_request: string
          p_score: number
        }
        Returns: Database["public"]["Enums"]["request_status"]
      }
      request_raised_cents: { Args: { p_request: string }; Returns: number }
      resolve_fraud_signal: { Args: { p_id: number }; Returns: undefined }
      resume_ended_pauses: { Args: never; Returns: number }
      resume_loan: {
        Args: { p_loan: string }
        Returns: Database["public"]["Enums"]["loan_status"]
      }
      run_pool_allocation: {
        Args: {
          p_available_cents: number
          p_fund: Database["public"]["Enums"]["fund"]
        }
        Returns: string
      }
      set_loan_schedule: {
        Args: { p_first_due: string; p_loan: string; p_months: number }
        Returns: undefined
      }
      set_loan_terms: {
        Args: {
          p_default_plan: Database["public"]["Enums"]["default_plan"]
          p_loan: string
          p_pause_months_per_year: number
          p_payment_day: number
        }
        Returns: undefined
      }
      sign_loan: {
        Args: { p_loan: string }
        Returns: Database["public"]["Enums"]["loan_status"]
      }
      submit_request: {
        Args: { p_request: string }
        Returns: Database["public"]["Enums"]["request_status"]
      }
      subscription_amount: {
        Args: { p_monthly_income_cents: number; p_version?: number }
        Returns: number
      }
      withdraw_request: { Args: { p_request: string }; Returns: undefined }
    }
    Enums: {
      allocation_target: "car_damage" | "home_help" | "highest_score"
      appeal_status: "open" | "upheld" | "denied"
      asset_kind: "vehicle" | "home"
      contribution_source: "gift" | "loan" | "pool"
      contribution_status: "pledged" | "captured" | "released" | "refunded"
      default_plan: "mediate" | "forgive" | "repay_on_sale"
      evidence_kind:
        | "photo"
        | "police_report"
        | "estimate"
        | "invoice"
        | "statement"
        | "contract"
        | "other"
      fund: "protection" | "home_fund" | "people"
      funding_mode: "people" | "pool" | "both"
      income_method: "bank_link" | "tax_return" | "self_attested"
      loan_status:
        | "proposed"
        | "signed"
        | "active"
        | "paused"
        | "repaid"
        | "forgiven"
        | "defaulted"
        | "cancelled"
      member_role: "reviewer" | "panel" | "admin"
      member_status: "pending_verification" | "active" | "suspended" | "closed"
      payee_kind:
        | "repair_shop"
        | "lender"
        | "seller"
        | "contractor"
        | "title_company"
      payment_status: "pending" | "captured" | "failed" | "refunded"
      payout_status: "pending" | "sent" | "failed" | "returned"
      redaction_status: "pending" | "auto_done" | "confirmed" | "rejected"
      request_kind:
        | "car_damage"
        | "car_deductible"
        | "home_repair"
        | "down_payment"
        | "mortgage_gap"
        | "loan_payoff"
      request_status:
        | "draft"
        | "scoring"
        | "needs_evidence"
        | "in_review"
        | "open"
        | "funded"
        | "paid"
        | "refused"
        | "withdrawn"
        | "expired"
      review_decision: "approve" | "needs_evidence" | "refuse" | "escalate"
      verification_status: "pending" | "verified" | "suspended"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {
      allocation_target: ["car_damage", "home_help", "highest_score"],
      appeal_status: ["open", "upheld", "denied"],
      asset_kind: ["vehicle", "home"],
      contribution_source: ["gift", "loan", "pool"],
      contribution_status: ["pledged", "captured", "released", "refunded"],
      default_plan: ["mediate", "forgive", "repay_on_sale"],
      evidence_kind: [
        "photo",
        "police_report",
        "estimate",
        "invoice",
        "statement",
        "contract",
        "other",
      ],
      fund: ["protection", "home_fund", "people"],
      funding_mode: ["people", "pool", "both"],
      income_method: ["bank_link", "tax_return", "self_attested"],
      loan_status: [
        "proposed",
        "signed",
        "active",
        "paused",
        "repaid",
        "forgiven",
        "defaulted",
        "cancelled",
      ],
      member_role: ["reviewer", "panel", "admin"],
      member_status: ["pending_verification", "active", "suspended", "closed"],
      payee_kind: [
        "repair_shop",
        "lender",
        "seller",
        "contractor",
        "title_company",
      ],
      payment_status: ["pending", "captured", "failed", "refunded"],
      payout_status: ["pending", "sent", "failed", "returned"],
      redaction_status: ["pending", "auto_done", "confirmed", "rejected"],
      request_kind: [
        "car_damage",
        "car_deductible",
        "home_repair",
        "down_payment",
        "mortgage_gap",
        "loan_payoff",
      ],
      request_status: [
        "draft",
        "scoring",
        "needs_evidence",
        "in_review",
        "open",
        "funded",
        "paid",
        "refused",
        "withdrawn",
        "expired",
      ],
      review_decision: ["approve", "needs_evidence", "refuse", "escalate"],
      verification_status: ["pending", "verified", "suspended"],
    },
  },
} as const

