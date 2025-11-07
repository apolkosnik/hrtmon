
;HRTmon Amiga system monitor
;Copyright (C) 1991-1998 Alain Malek Alain.Malek@cryogen.com
;
;This program is free software; you can redistribute it and/or
;modify it under the terms of the GNU General Public License
;as published by the Free Software Foundation; either version 2
;of the License, or (at your option) any later version.
;
;This program is distributed in the hope that it will be useful,
;but WITHOUT ANY WARRANTY; without even the implied warranty of
;MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;GNU General Public License for more details.
;
;You can find the full GNU GPL online at: http://www.gnu.org

;-------------- Search copper-list -----------------------------

cmd_cop		moveq	#0,d5
		move.l	max_chip,d6
		bsr	evaluate
		bmi.w	illegal_addr
		bgt.w	.norange
		move.l	d0,d5
		and.w	#$fffe,d5
		bsr	evaluate
		bmi.w	illegal_addr
		bgt.w	.norange
		move.l	d0,d6
		and.w	#$fffe,d6
.norange	cmp.l	d5,d6
		bls.w	illegal_addr

		move.l	d5,a0
		move.l	d6,a1
		bsr	search_cop
		tst.l	d7
		beq.b	.cop

		lea.l	copfailed_txt(pc),a0
		bsr	print
		bra.b	.out

.cop		lea.l	copfound_txt(pc),a0
		bsr	print
		moveq	#8,d1
		move.l	custom+$80,d0
		bsr	print_hexCR

.out		bra.w	end_command

copfailed_txt	dc.b "Couldn't find copper-list",$a,0
copfound_txt	dc.b "Copper-list found at $",0
		even


;-> a0-a1 = search range
;<- d0 = copper address
;<- d7 = success / failed

search_cop	movem.l	d1/a2-a3,-(a7)
		bsr	remove_pic
		move.w	#$8380,$dff096
		move.w	#$2700,sr

		bsr	find_cop_int

		moveq	#-1,d7

		moveq	#-2,d1
.seek		cmp.l	a1,a0
		bge.w	.end
		cmp.l	(a0),d1
		beq.b	.try
		addq.l	#2,a0
		bra.b	.seek

.try		move.l	a0,a2
		addq.l	#2,a0

		move.l	a2,a3
		subq.l	#4,a2
		bsr	.test_cop
		beq.b	.seek

.up		lea.l	-$200(a2),a2
		cmp.l	#0,a2
		bge.b	.okmin
		suba.l	a2,a2
		bra.b	.down
.okmin		bsr	.test_cop
		bne.b	.up

.down		lea.l	$20(a2),a2
		cmp.l	a3,a2
		ble.b	.okmax
		move.l	a3,a2
		bra.b	.up2
.okmax		bsr	.test_cop
		beq.b	.down

.up2		subq.l	#4,a2
		bsr	.test_cop
		bne.b	.up2

		addq.l	#4,a2

		moveq	#0,d7
		move.l	a2,d0
		move.l	d0,custom+$80

.end		move.l	d0,-(a7)
		moveq	#0,d0
		jsr	analyse_copper
		move.l	(a7)+,d0

		bsr	set_pic
		move.w	#$80,$dff096
		move.w	#$7fff,$dff09c
		move.w	#$2000,sr
		movem.l	(a7)+,d1/a2-a3
		rts

.test_cop	movem.l	d0/d6,-(a7)

		move.w	(a2),d0
		btst	#0,d0
		beq.b	.move
		cmp.b	#$f0,d0
		bhi.b	.nocop
		bra.b	.okwait
.move		tst.w	d0
		beq.b	.nocop
		cmp.w	#$1fe,d0
		bls.b	.okwait
.nocop		moveq	#0,d0
		bra.b	.exittest

.okwait		move.w	cop_int(pc),$dff09c
		move.l	(a2),d6
		move.l	#$009c8000,d0
		or.w	cop_int(pc),d0
		move.l	d0,(a2)
;		move.w	#$0,$dff088
		move.b	#0,$bfe801
.wait		cmp.b	#2,$bfe801
		bls.b	.wait
		move.w	$dff01e,d0
		move.l	d6,(a2)
		and.w	cop_int(pc),d0
.exittest	movem.l	(a7)+,d0/d6
		rts

cop_int		dc.w 0

;-------------- find a 'free' interrupt for copper searching -----

find_cop_int	movem.l	d0-d1/a0,-(a7)
		move.w	#$10,d1			;copint
		bsr.b	.test
		beq.b	.ok_int

		move.w	#4,d1			;softint
		bsr.b	.test
		beq.b	.ok_int

		lea.l	.warning_txt(pc),a0
		bsr	print

.ok_int		move.w	d1,cop_int
		movem.l	(a7)+,d0-d1/a0
		rts

.test		move.w	d1,$dff09c
;		move.w	#$0,$dff088
		move.b	#0,$bfe801
.wait		cmp.b	#2,$bfe801
		bls.b	.wait
		move.w	$dff01e,d0
		and.w	d1,d0
		rts

.warning_txt	dc.b "Couldn't find a free interrupt !",$a,0
		even

;----------------------------------------------------------
;-------------- analyse the actual copper-list and --------
;-------------- update custom registers -------------------

;-> d0=pic_no (stop the scan after the d0th write to $DFF100, 0=scan all)

analyse_copper	movem.l	d0-a4,-(a7)
		move.w	d0,d6
		bne.b	.okpara
		moveq	#-1,d6
.okpara		lea.l	custom,a3
		move.l	$80(a3),d0	;get copper 1 start
		bsr.b	.analyse
		movem.l	(a7)+,d0-a4
		rts


;-> d0=ptr on copper-list

.analyse	lea.l	custom,a3
		lea.l	paletteH-$180,a1
		move.w	($106,a3),d3
		btst	#9,d3		;low or high bits palette
		beq.b	.high
		lea.l	paletteL-$180,a1
.high		rol.w	#3,d3
		and.w	#%111,d3	;d1=bank no.
		lsl.w	#6,d3		;*32*2
		add.w	d3,a1

		lea.l	move_list,a2
		btst	#0,d0
		bne.w	.end		;copper list at odd address ?
		move.l	d0,a0

.loop		move.l	a0,a4
		bsr	reloc_pic
		movem.w	(a4)+,d0/d1	;read actual instr.
		addq.l	#4,a0		;go next instr.
		btst	#0,d0		;wait/skip or move instr. ?
		bne.b	.waitinst

		cmp.w	#$200,d0	;legal custom register ?
		bcc.w	.end

		cmp.w	#$88,d0		;cop1jmp ?
		bne.b	.nojmp1
		move.l	($80,a3),a0	;do the jmp to cop1
		bra.b	.loop
.nojmp1		cmp.w	#$8a,d0		;cop2jmp ?
		bne.b	.nojmp2
		move.l	($84,a3),a0	;do the jmp to cop2
		bra.b	.loop

.nojmp2		cmp.w	#$180,d0
		blt.b	.nocolor
		cmp.w	#$1be,d0
		bgt.b	.nocolor
		move.w	d1,(a1,d0.w)	;copy in actual palette bank

.nocolor	cmp.w	#$106,d0
		bne.b	.nobplcon3

		lea.l	paletteH-$180,a1
		move.w	d1,d3
		btst	#9,d3		;low or high bits palette
		beq.b	.high2
		lea.l	paletteL-$180,a1
.high2		rol.w	#3,d3
		and.w	#%111,d3	;d1=bank no.
		lsl.w	#6,d3		;*32*2
		add.w	d3,a1

.nobplcon3	move.w	d0,d2
		lsr.w	#1,d2
		tst.b	(a2,d2.w)	;do I need to copy this value ?
		beq.b	.nocopy
		move.w	d1,(a3,d0.w)	;copy in custom
		cmp.w	#$100,d0
		bne.b	.no100
		subq.w	#1,d6		;dec(pic_no)
		beq.b	.end
.no100		bra.b	.nocopy

.waitinst	cmp.w	#$ffff,d0
		beq.b	.end

.nocopy		bra.w	.loop

.end		rts

		cnop 0,4
;-------------- flags signaling registers to copy ---------
;-------------- from copper-list to custom ----------------

move_list	dcb.b $40,0		;$000-$07e
		dc.b -1,-1		;$80,$82	;cop1
		dc.b -1,-1		;$84,$86	;cop2
		dc.b 0,0,0		;$88,$8a,$8c
		dc.b -1,-1,-1,-1	;$8e,$90,$92,$94
		dcb.b $25,0		;$96-$de
		dcb.b $10,-1		;$e0-$fe
		dcb.b 7,-1		;$100-$10c
		dcb.b 9,0		;$10e-$11e
		dcb.b $10,-1		;$120-$13e
		dcb.b $20,0		;$140-$17e
		dcb.b $20,-1		;$180-$1be
		dcb.b $d,0		;$1c0-$1d8
		dc.b 0			;$1da
		dc.b -1			;$1dc
		dc.b -1,-1,-1		;$1de-$1e2
		dc.b -1			;$1e4
		dcb.b $b,0		;$1e6-$1fa
		dc.b -1			;$1fc
		dc.b 0			;$1fe

;-------------- Disassemble copper-list ------------------------

cmd_copd	bsr	evaluate
		bmi.b	.use_current
		move.l	d0,a4
		bra.b	.start

.use_current	move.l	custom+$80,a4	;use current copper1 address

.start		and.w	#$fffe,a4	;ensure even address
		move.l	a4,a5		;save start address

		moveq	#0,d5		;line counter
.loop		cmp.w	#18,d5		;max lines per screen
		bge.b	.done

		lea.l	output,a0
		move.l	a5,d0
		moveq	#6,d1
		bsr	print_hex
		lea.l	.colon(pc),a0
		bsr	print

		move.l	a5,a0
		bsr	reloc_pic
		move.w	(a4)+,d2	;d2 = word1 (register/position)
		move.w	(a4)+,d3	;d3 = word2 (value/mask)

		;print hex values
		lea.l	output,a0
		move.w	d2,d0
		moveq	#4,d1
		bsr	print_hex
		lea.l	.space(pc),a0
		bsr	print

		lea.l	output,a0
		move.w	d3,d0
		moveq	#4,d1
		bsr	print_hex
		lea.l	.space2(pc),a0
		bsr	print

		;decode instruction
		move.w	d2,d0
		btst	#0,d0		;check if WAIT/SKIP or MOVE
		bne.b	.wait_skip

		;MOVE instruction
		lea.l	.move_txt(pc),a0
		bsr	print
		lea.l	output,a0
		move.w	d2,d0
		and.w	#$1fe,d0
		moveq	#3,d1
		bsr	print_hex
		lea.l	.comma(pc),a0
		bsr	print

		lea.l	output,a0
		move.w	d3,d0
		moveq	#4,d1
		bsr	print_hex

		;print register name if known
		move.w	d2,d0
		bsr	.print_regname
		bsr	print_cr
		bra.b	.next

.wait_skip	cmp.w	#$ffff,d2
		bne.b	.not_end

		;END instruction
		lea.l	.end_txt(pc),a0
		bsr	print
		bsr	print_cr
		addq.w	#1,d5
		bra.b	.done

.not_end	btst	#15,d2
		beq.b	.is_wait

		;SKIP instruction
		lea.l	.skip_txt(pc),a0
		bsr	print
		bra.b	.wait_common

.is_wait	;WAIT instruction
		lea.l	.wait_txt(pc),a0
		bsr	print

.wait_common	move.w	d2,d0
		lsr.w	#8,d0
		and.w	#$ff,d0
		lea.l	output,a0
		moveq	#2,d1
		bsr	print_hex
		lea.l	.comma(pc),a0
		bsr	print

		move.w	d2,d0
		lsr.w	#1,d0
		and.w	#$7f,d0
		lea.l	output,a0
		moveq	#2,d1
		bsr	print_hex

		;print mask
		lea.l	.mask_txt(pc),a0
		bsr	print
		lea.l	output,a0
		move.w	d3,d0
		moveq	#4,d1
		bsr	print_hex
		bsr	print_cr

.next		addq.l	#4,a5
		addq.w	#1,d5
		bra.w	.loop

.done		bra.w	end_command

;print register name for custom register offsets
.print_regname	movem.l	d0-d1/a0,-(a7)
		and.w	#$1fe,d0
		lea.l	.reg_names(pc),a0
		moveq	#0,d1
.find_reg	tst.b	(a0)
		beq.b	.reg_done
		cmp.w	(a0),d0
		beq.b	.found_reg
		addq.l	#2,a0
.skip_name	tst.b	(a0)+
		bne.b	.skip_name
		bra.b	.find_reg

.found_reg	addq.l	#2,a0
		lea.l	.space3(pc),a1
		move.l	a1,-(a7)
		bsr	print
		move.l	(a7)+,a0
		bsr	print
		move.l	a0,-(a7)
		bsr	print
		move.l	(a7)+,a0
		bsr	print

.reg_done	movem.l	(a7)+,d0-d1/a0
		rts

;table of register offsets and names
.reg_names	dc.w $080
		dc.b "COP1LC",0
		dc.w $084
		dc.b "COP2LC",0
		dc.w $088
		dc.b "COPJMP1",0
		dc.w $08a
		dc.b "COPJMP2",0
		dc.w $08e
		dc.b "DIWSTRT",0
		dc.w $090
		dc.b "DIWSTOP",0
		dc.w $092
		dc.b "DDFSTRT",0
		dc.w $094
		dc.b "DDFSTOP",0
		dc.w $096
		dc.b "DMACON",0
		dc.w $09a
		dc.b "INTENA",0
		dc.w $09c
		dc.b "INTREQ",0
		dc.w $100
		dc.b "BPLCON0",0
		dc.w $102
		dc.b "BPLCON1",0
		dc.w $104
		dc.b "BPLCON2",0
		dc.w $106
		dc.b "BPLCON3",0
		dc.w $108
		dc.b "BPL1MOD",0
		dc.w $10a
		dc.b "BPL2MOD",0
		dc.w $0e0
		dc.b "BPL1PTH",0
		dc.w $0e2
		dc.b "BPL1PTL",0
		dc.w $0e4
		dc.b "BPL2PTH",0
		dc.w $0e6
		dc.b "BPL2PTL",0
		dc.w $0e8
		dc.b "BPL3PTH",0
		dc.w $0ea
		dc.b "BPL3PTL",0
		dc.w $0ec
		dc.b "BPL4PTH",0
		dc.w $0ee
		dc.b "BPL4PTL",0
		dc.w $0f0
		dc.b "BPL5PTH",0
		dc.w $0f2
		dc.b "BPL5PTL",0
		dc.w $0f4
		dc.b "BPL6PTH",0
		dc.w $0f6
		dc.b "BPL6PTL",0
		dc.w $0f8
		dc.b "BPL7PTH",0
		dc.w $0fa
		dc.b "BPL7PTL",0
		dc.w $0fc
		dc.b "BPL8PTH",0
		dc.w $0fe
		dc.b "BPL8PTL",0
		dc.w $120
		dc.b "SPR0PTH",0
		dc.w $122
		dc.b "SPR0PTL",0
		dc.w $124
		dc.b "SPR1PTH",0
		dc.w $126
		dc.b "SPR1PTL",0
		dc.w $128
		dc.b "SPR2PTH",0
		dc.w $12a
		dc.b "SPR2PTL",0
		dc.w $12c
		dc.b "SPR3PTH",0
		dc.w $12e
		dc.b "SPR3PTL",0
		dc.w $130
		dc.b "SPR4PTH",0
		dc.w $132
		dc.b "SPR4PTL",0
		dc.w $134
		dc.b "SPR5PTH",0
		dc.w $136
		dc.b "SPR5PTL",0
		dc.w $138
		dc.b "SPR6PTH",0
		dc.w $13a
		dc.b "SPR6PTL",0
		dc.w $13c
		dc.b "SPR7PTH",0
		dc.w $13e
		dc.b "SPR7PTL",0
		dc.w $180
		dc.b "COLOR00",0
		dc.b 0		;end marker
		even

.colon		dc.b ": ",0
.space		dc.b " ",0
.space2		dc.b "  ",0
.space3		dc.b " (",0
.comma		dc.b ",",0
.move_txt	dc.b "MOVE.W $",0
.wait_txt	dc.b "WAIT ",0
.skip_txt	dc.b "SKIP ",0
.end_txt	dc.b "END",0
.mask_txt	dc.b ", mask=$",0
.close_txt	dc.b ")",0
		even

