; The entire sound engine. Uses section "audio" in WRAM.

; Interfaces are in bank 0.

; Notable functions:
; 	FadeMusic
; 	PlayStereoSFX

_MapSetup_Sound_Off:: ; e8000
; restart sound operation
; clear all relevant hardware registers & wram
	push hl
	push de
	push bc
	push af
	call MusicOff
	ld hl, rNR50 ; channel control registers
	xor a
	ld [hli], a ; rNR50 ; volume/vin
	ld [hli], a ; rNR51 ; sfx channels
	ld a, $80 ; all channels on
	ld [hli], a ; ff26 ; music channels

	ld hl, rNR10 ; sound channel registers
	ld e, $4 ; number of channels
.clearsound
;   sound channel   1      2      3      4
	xor a
	ld [hli], a ; rNR10, rNR20, rNR30, rNR40 ; sweep = 0

	ld [hli], a ; rNR11, rNR21, rNR31, rNR41 ; length/wavepattern = 0
	ld a, $8
	ld [hli], a ; rNR12, rNR22, rNR32, rNR42 ; envelope = 0
	xor a
	ld [hli], a ; rNR13, rNR23, rNR33, rNR43 ; frequency lo = 0
	ld a, $80
	ld [hli], a ; rNR14, rNR24, rNR34, rNR44 ; restart sound (freq hi = 0)
	dec e
	jr nz, .clearsound

	ld hl, Channel1 ; start of channel data
	ld de, $1bf ; length of area to clear (entire sound wram area)
.clearchannels ; clear Channel1-$c2bf
	xor a
	ld [hli], a
	dec de
	ld a, e
	or d
	jr nz, .clearchannels
	ld a, $77 ; max
	ld [Volume], a
	call MusicOn
	pop af
	pop bc
	pop de
	pop hl
	ret

; e803d

MusicFadeRestart: ; e803d
; restart but keep the music id to fade in to
	ld a, [MusicFadeIDHi]
	push af
	ld a, [MusicFadeIDLo]
	push af
	call _MapSetup_Sound_Off
	pop af
	ld [MusicFadeIDLo], a
	pop af
	ld [MusicFadeIDHi], a
	ret

; e8051

MusicOn: ; e8051
	ld a, 1
	ld [MusicPlaying], a
	ret

; e8057

MusicOff: ; e8057
	xor a
	ld [MusicPlaying], a
	ret

; e805c

_UpdateSound:: ; e805c
; called once per frame
	; no use updating audio if it's not playing
	ld a, [MusicPlaying]
	and a
	ret z
	; start at ch1
	xor a
	ld [CurChannel], a ; just
	ld [SoundOutput], a ; off
	ld bc, Channel1
.loop
	; is the channel active?
	ld hl, Channel1Flags - Channel1
	add hl, bc
	bit SOUND_CHANNEL_ON, [hl]
	jp z, .nextchannel
	; check time left in the current note
	ld hl, Channel1NoteDuration - Channel1
	add hl, bc
	ld a, [hl]
	cp $2 ; 1 or 0?
	jr c, .noteover
	dec [hl]
	jr .asm_e8093

.noteover
	; reset vibrato delay
	ld hl, Channel1VibratoDelay - Channel1
	add hl, bc
	ld a, [hl]
	ld hl, Channel1VibratoDelayCount - Channel1
	add hl, bc
	ld [hl], a
	; turn vibrato off for now
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	res SOUND_UNKN_09, [hl]
	; get next note
	call ParseMusic
.asm_e8093
	;
	call Functione84f9
	; duty cycle
	ld hl, Channel1DutyCycle - Channel1
	add hl, bc
	ld a, [hli]
	ld [wCurTrackDuty], a
	; intensity
	ld a, [hli]
	ld [wCurTrackIntensity], a
	; frequency
	ld a, [hli]
	ld [wCurTrackFrequency], a
	ld a, [hl]
	ld [wCurTrackFrequency + 1], a
	;
	call Functione8466 ; handle vibrato and other things
	call HandleNoise
	; turn off music when playing sfx?
	ld a, [SFXPriority]
	and a
	jr z, .next
	; are we in a sfx channel right now?
	ld a, [CurChannel]
	cp $4
	jr nc, .next
	; are any sfx channels active?
	; if so, mute
	ld hl, Channel5Flags
	bit SOUND_CHANNEL_ON, [hl]
	jr nz, .restnote
	ld hl, Channel6Flags
	bit SOUND_CHANNEL_ON, [hl]
	jr nz, .restnote
	ld hl, Channel7Flags
	bit SOUND_CHANNEL_ON, [hl]
	jr nz, .restnote
	ld hl, Channel8Flags
	bit SOUND_CHANNEL_ON, [hl]
	jr z, .next
.restnote
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_REST, [hl] ; Rest
.next
	; are we in a sfx channel right now?
	ld a, [CurChannel]
	cp $4 ; sfx
	jr nc, .asm_e80ee
	ld hl, Channel5Flags - Channel1
	add hl, bc
	bit SOUND_CHANNEL_ON, [hl]
	jr nz, .asm_e80fc
.asm_e80ee
	call UpdateChannels
	ld hl, Channel1Tracks - Channel1
	add hl, bc
	ld a, [SoundOutput]
	or [hl]
	ld [SoundOutput], a
.asm_e80fc
	; clear note flags
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	xor a
	ld [hl], a
.nextchannel
	; next channel
	ld hl, Channel2 - Channel1
	add hl, bc
	ld c, l
	ld b, h
	ld a, [CurChannel]
	inc a
	ld [CurChannel], a
	cp $8 ; are we done?
	jp nz, .loop ; do it all again

	call PlayDanger
	; fade music in/out
	call FadeMusic
	; write volume to hardware register
	ld a, [Volume]
	ld [rNR50], a
	; write SO on/off to hardware register
	ld a, [SoundOutput]
	ld [rNR51], a
	ret

; e8125

UpdateChannels: ; e8125
	ld hl, .ChannelFnPtrs
	ld a, [CurChannel]
	and $7
	add a
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	jp [hl]


.ChannelFnPtrs
	dw .Channel1
	dw .Channel2
	dw .Channel3
	dw .Channel4
; sfx ch ptrs are identical to music chs
; ..except 5
	dw .Channel5
	dw .Channel6
	dw .Channel7
	dw .Channel8

.Channel1
	ld a, [Danger]
	bit 7, a
	ret nz
.Channel5
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	bit NOTE_UNKN_3, [hl]
	jr z, .asm_e8159
	;
	ld a, [SoundInput]
	ld [rNR10], a
.asm_e8159
	bit NOTE_REST, [hl] ; rest
	jr nz, .ch1rest
	bit NOTE_UNKN_4, [hl]
	jr nz, .asm_e81a2
	bit NOTE_UNKN_1, [hl]
	jr nz, .asm_e816b
	bit NOTE_UNKN_6, [hl]
	jr nz, .asm_e8184
	jr .asm_e8175

.asm_e816b
	ld a, [wCurTrackFrequency]
	ld [rNR13], a
	ld a, [wCurTrackFrequency + 1]
	ld [rNR14], a
.asm_e8175
	bit NOTE_UNKN_0, [hl]
	ret z
	ld a, [wCurTrackDuty]
	ld d, a
	ld a, [rNR11]
	and $3f ; sound length
	or d
	ld [rNR11], a
	ret

.asm_e8184
	ld a, [wCurTrackDuty]
	ld d, a
	ld a, [rNR11]
	and $3f ; sound length
	or d
	ld [rNR11], a
	ld a, [wCurTrackFrequency]
	ld [rNR13], a
	ret

.ch1rest
	ld a, [rNR52]
	and %10001110 ; ch1 off
	ld [rNR52], a
	ld hl, rNR10
	call ClearChannel
	ret

.asm_e81a2
	ld hl, wCurTrackDuty
	ld a, $3f ; sound length
	or [hl]
	ld [rNR11], a
	ld a, [wCurTrackIntensity]
	ld [rNR12], a
	ld a, [wCurTrackFrequency]
	ld [rNR13], a
	ld a, [wCurTrackFrequency + 1]
	or $80
	ld [rNR14], a
	ret

.Channel2
.Channel6
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	bit NOTE_REST, [hl] ; rest
	jr nz, .ch2rest
	bit NOTE_UNKN_4, [hl]
	jr nz, .asm_e8204
	bit NOTE_UNKN_6, [hl]
	jr nz, .asm_e81e6
	bit NOTE_UNKN_0, [hl]
	ret z
	ld a, [wCurTrackDuty]
	ld d, a
	ld a, [rNR21]
	and $3f ; sound length
	or d
	ld [rNR21], a
	ret

.asm_e81db ; unused
	ld a, [wCurTrackFrequency]
	ld [rNR23], a
	ld a, [wCurTrackFrequency + 1]
	ld [rNR24], a
	ret

.asm_e81e6
	ld a, [wCurTrackDuty]
	ld d, a
	ld a, [rNR21]
	and $3f ; sound length
	or d
	ld [rNR21], a
	ld a, [wCurTrackFrequency]
	ld [rNR23], a
	ret

.ch2rest
	ld a, [rNR52]
	and %10001101 ; ch2 off
	ld [rNR52], a
	ld hl, rNR20
	call ClearChannel
	ret

.asm_e8204
	ld hl, wCurTrackDuty
	ld a, $3f ; sound length
	or [hl]
	ld [rNR21], a
	ld a, [wCurTrackIntensity]
	ld [rNR22], a
	ld a, [wCurTrackFrequency]
	ld [rNR23], a
	ld a, [wCurTrackFrequency + 1]
	or $80 ; initial (restart)
	ld [rNR24], a
	ret

.Channel3
.Channel7
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	bit NOTE_REST, [hl] ; rest
	jr nz, .ch3rest
	bit NOTE_UNKN_4, [hl]
	jr nz, .asm_e824d
	bit NOTE_UNKN_6, [hl]
	jr nz, .asm_e823a
	ret

.asm_e822f ; unused
	ld a, [wCurTrackFrequency]
	ld [rNR33], a
	ld a, [wCurTrackFrequency + 1]
	ld [rNR34], a
	ret

.asm_e823a
	ld a, [wCurTrackFrequency]
	ld [rNR33], a
	ret

.ch3rest
	ld a, [rNR52]
	and %10001011 ; ch3 off
	ld [rNR52], a
	ld hl, rNR30
	call ClearChannel
	ret

.asm_e824d
	ld a, $3f
	ld [rNR31], a
	xor a
	ld [rNR30], a
	call .asm_e8268
	ld a, $80
	ld [rNR30], a
	ld a, [wCurTrackFrequency]
	ld [rNR33], a
	ld a, [wCurTrackFrequency + 1]
	or $80
	ld [rNR34], a
	ret

.asm_e8268
	push hl
	ld a, [wCurTrackIntensity]
	and $f ; only 0-9 are valid
	ld l, a
	ld h, 0
	; hl << 4
	; each wavepattern is $f bytes long
	; so seeking is done in $10s
rept 4
	add hl, hl
endr
	ld de, WaveSamples
	add hl, de
	; load wavepattern into rWave_0-rWave_f
	ld a, [hli]
	ld [rWave_0], a
	ld a, [hli]
	ld [rWave_1], a
	ld a, [hli]
	ld [rWave_2], a
	ld a, [hli]
	ld [rWave_3], a
	ld a, [hli]
	ld [rWave_4], a
	ld a, [hli]
	ld [rWave_5], a
	ld a, [hli]
	ld [rWave_6], a
	ld a, [hli]
	ld [rWave_7], a
	ld a, [hli]
	ld [rWave_8], a
	ld a, [hli]
	ld [rWave_9], a
	ld a, [hli]
	ld [rWave_a], a
	ld a, [hli]
	ld [rWave_b], a
	ld a, [hli]
	ld [rWave_c], a
	ld a, [hli]
	ld [rWave_d], a
	ld a, [hli]
	ld [rWave_e], a
	ld a, [hli]
	ld [rWave_f], a
	pop hl
	ld a, [wCurTrackIntensity]
	and $f0
	sla a
	ld [rNR32], a
	ret

.Channel4
.Channel8
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	bit NOTE_REST, [hl] ; rest
	jr nz, .ch4rest
	bit NOTE_UNKN_4, [hl]
	jr nz, .asm_e82d4
	ret

.asm_e82c1 ; unused
	ld a, [wCurTrackFrequency]
	ld [rNR43], a
	ret

.ch4rest
	ld a, [rNR52]
	and %10000111 ; ch4 off
	ld [rNR52], a
	ld hl, rNR40
	call ClearChannel
	ret

.asm_e82d4
	ld a, $3f ; sound length
	ld [rNR41], a
	ld a, [wCurTrackIntensity]
	ld [rNR42], a
	ld a, [wCurTrackFrequency]
	ld [rNR43], a
	ld a, $80
	ld [rNR44], a
	ret

; e82e7

_CheckSFX: ; e82e7
; return carry if any sfx channels are active
	ld hl, Channel5Flags
	bit SOUND_CHANNEL_ON, [hl]
	jr nz, .sfxon
	ld hl, Channel6Flags
	bit SOUND_CHANNEL_ON, [hl]
	jr nz, .sfxon
	ld hl, Channel7Flags
	bit SOUND_CHANNEL_ON, [hl]
	jr nz, .sfxon
	ld hl, Channel8Flags
	bit SOUND_CHANNEL_ON, [hl]
	jr nz, .sfxon
	and a
	ret

.sfxon
	scf
	ret

; e8307

PlayDanger: ; e8307
	ld a, [Danger]
	bit 7, a
	ret z
	and $7f
	ld d, a
	call _CheckSFX
	jr c, .asm_e8335
	and a
	jr z, .asm_e8323
	cp 16 ; halfway
	jr z, .asm_e831e
	jr .asm_e8335

.asm_e831e
	ld hl, Tablee8354
	jr .updatehw

.asm_e8323
	ld hl, Tablee8350
.updatehw
	xor a
	ld [rNR10], a ; sweep off
	ld a, [hli]
	ld [rNR11], a ; sound length / duty cycle
	ld a, [hli]
	ld [rNR12], a ; ch1 volume envelope
	ld a, [hli]
	ld [rNR13], a ; ch1 frequency lo
	ld a, [hli]
	ld [rNR14], a ; ch1 frequency hi
.asm_e8335
	ld a, d
	inc a
	cp 30
	jr c, .asm_e833c
	xor a
.asm_e833c
	or $80
	ld [Danger], a
	; is hw ch1 on?
	ld a, [SoundOutput]
	and $11
	ret nz
	; if not, turn it on
	ld a, [SoundOutput]
	or $11
	ld [SoundOutput], a
	ret

; e8350

Tablee8350: ; e8350
	db $80 ; duty 50%
	db $e2 ; volume 14, envelope decrease sweep 2
	db $50 ; frequency: $750
	db $87 ; restart sound
; e8354

Tablee8354: ; e8354
	db $80 ; duty 50%
	db $e2 ; volume 14, envelope decrease sweep 2
	db $ee ; frequency: $6ee
	db $86 ; restart sound
; e8358

FadeMusic: ; e8358
; fade music if applicable
; usage:
;	write to MusicFade
;	song fades out at the given rate
;	load song id in MusicFadeID
;	fade new song in
; notes:
;	max # frames per volume level is $3f

	; fading?
	ld a, [MusicFade]
	and a
	ret z
	; has the count ended?
	ld a, [MusicFadeCount]
	and a
	jr z, .update
	; count down
	dec a
	ld [MusicFadeCount], a
	ret

.update
	ld a, [MusicFade]
	ld d, a
	; get new count
	and $3f
	ld [MusicFadeCount], a
	; get SO1 volume
	ld a, [Volume]
	and $7
	; which way are we fading?
	bit 7, d
	jr nz, .fadein
	; fading out
	and a
	jr z, .novolume
	dec a
	jr .updatevolume


.novolume
	; make sure volume is off
	xor a
	ld [Volume], a
	; did we just get on a bike?
	ld a, [PlayerState]
	cp $1 ; bicycle
	jr z, .bicycle
	push bc
	; restart sound
	call MusicFadeRestart
	; get new song id
	ld a, [MusicFadeIDLo]
	and a
	jr z, .quit ; this assumes there are fewer than 256 songs!
	ld e, a
	ld a, [MusicFadeIDHi]
	ld d, a
	; load new song
	call _PlayMusic
.quit
	; cleanup
	pop bc
	; stop fading
	xor a
	ld [MusicFade], a
	ret

.bicycle
	push bc
	; restart sound
	call MusicFadeRestart
	; this turns the volume up
	; turn it back down
	xor a
	ld [Volume], a
	; get new song id
	ld a, [MusicFadeIDLo]
	ld e, a
	ld a, [MusicFadeIDHi]
	ld d, a
	; load new song
	call _PlayMusic
	pop bc
	; fade in
	ld hl, MusicFade
	set 7, [hl]
	ret

.fadein
	; are we done?
	cp $7
	jr nc, .maxvolume
	; inc volume
	inc a
	jr .updatevolume

.maxvolume
	; we're done
	xor a
	ld [MusicFade], a
	ret

.updatevolume
	; hi = lo
	ld d, a
	swap a
	or d
	ld [Volume], a
	ret

; e83d1

LoadNote: ; e83d1
	; check mute??
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	bit SOUND_UNKN_09, [hl]
	ret z
	; get note duration
	ld hl, Channel1NoteDuration - Channel1
	add hl, bc
	ld a, [hl]
	ld hl, wc297 ; ????
	sub [hl]
	jr nc, .ok
	ld a, 1
.ok
	ld [hl], a
	; get frequency
	ld hl, Channel1Frequency - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	; ????
	ld hl, Channel1Field0x21 - Channel1
	add hl, bc
	ld a, e
	sub [hl]
	ld e, a
	ld a, d
	sbc a, 0
	ld d, a
	; ????
	ld hl, Channel1Field0x22 - Channel1
	add hl, bc
	sub [hl]
	jr nc, .greater_than
	; ????
	ld hl, Channel1Flags3 - Channel1
	add hl, bc
	set SOUND_UNKN_11, [hl]
	; get frequency
	ld hl, Channel1Frequency - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	; ????
	ld hl, Channel1Field0x21 - Channel1
	add hl, bc
	ld a, [hl]
	sub e
	ld e, a
	ld a, d
	sbc a, 0
	ld d, a
	; ????
	ld hl, Channel1Field0x22 - Channel1
	add hl, bc
	ld a, [hl]
	sub d
	ld d, a
	jr .resume

.greater_than
	; ????
	ld hl, Channel1Flags3 - Channel1
	add hl, bc
	res SOUND_UNKN_11, [hl]
	; get frequency
	ld hl, Channel1Frequency - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	; ????
	ld hl, Channel1Field0x21 - Channel1
	add hl, bc
	ld a, e
	sub [hl]
	ld e, a
	ld a, d
	sbc a, 0
	ld d, a
	; ????
	ld hl, Channel1Field0x22 - Channel1
	add hl, bc
	sub [hl]
	ld d, a
.resume
	push bc
	ld hl, wc297
	ld b, 0; loop count
.loop
	inc b
	ld a, e
	sub [hl]
	ld e, a
	jr nc, .loop
	ld a, d
	and a
	jr z, .quit
	dec d
	jr .loop

.quit
	ld a, e ; result
	add [hl]
	ld d, b ; loop count
	; ????
	pop bc
	ld hl, Channel1Field0x23 - Channel1
	add hl, bc
	ld [hl], d
	ld hl, Channel1Field0x24 - Channel1
	add hl, bc
	ld [hl], a
	; clear ????
	ld hl, Channel1Field0x25 - Channel1
	add hl, bc
	xor a
	ld [hl], a
	ret

; e8466

Functione8466: ; e8466
; handle vibrato and other things
; unknowns: wCurTrackDuty, wCurTrackFrequency
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	bit SOUND_DUTY, [hl] ; duty
	jr z, .next
	ld hl, Channel1Field0x1c - Channel1
	add hl, bc
	ld a, [hl]
	rlca
	rlca
	ld [hl], a
	and $c0
	ld [wCurTrackDuty], a
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_UNKN_0, [hl]
.next
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	bit SOUND_CRY_PITCH, [hl]
	jr z, .vibrato
	ld hl, Channel1CryPitch - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	ld hl, wCurTrackFrequency
	ld a, [hli]
	ld h, [hl]
	ld l, a
	add hl, de
	ld e, l
	ld d, h
	ld hl, wCurTrackFrequency
	ld [hl], e
	inc hl
	ld [hl], d
.vibrato
	; is vibrato on?
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	bit SOUND_VIBRATO, [hl] ; vibrato
	jr z, .quit
	; is vibrato active for this note yet?
	; is the delay over?
	ld hl, Channel1VibratoDelayCount - Channel1
	add hl, bc
	ld a, [hl]
	and a
	jr nz, .subexit
	; is the extent nonzero?
	ld hl, Channel1VibratoExtent - Channel1
	add hl, bc
	ld a, [hl]
	and a
	jr z, .quit
	; save it for later
	ld d, a
	; is it time to toggle vibrato up/down?
	ld hl, Channel1VibratoRate - Channel1
	add hl, bc
	ld a, [hl]
	and $f ; count
	jr z, .toggle
.subexit
	dec [hl]
	jr .quit

.toggle
	; refresh count
	ld a, [hl]
	swap [hl]
	or [hl]
	ld [hl], a
	; ????
	ld a, [wCurTrackFrequency]
	ld e, a
	; toggle vibrato up/down
	ld hl, Channel1Flags3 - Channel1
	add hl, bc
	bit SOUND_VIBRATO_DIR, [hl] ; vibrato up/down
	jr z, .down
; up
	; vibrato down
	res SOUND_VIBRATO_DIR, [hl]
	; get the delay
	ld a, d
	and $f ; lo
	;
	ld d, a
	ld a, e
	sub d
	jr nc, .asm_e84ef
	ld a, 0
	jr .asm_e84ef

.down
	; vibrato up
	set SOUND_VIBRATO_DIR, [hl]
	; get the delay
	ld a, d
	and $f0 ; hi
	swap a ; move it to lo
	;
	add e
	jr nc, .asm_e84ef
	ld a, $ff
.asm_e84ef
	ld [wCurTrackFrequency], a
	;
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_UNKN_6, [hl]
.quit
	ret

; e84f9

Functione84f9: ; e84f9
	; quit if ????
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	bit SOUND_UNKN_09, [hl]
	ret z
	; de = Frequency
	ld hl, Channel1Frequency - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	;
	ld hl, Channel1Flags3 - Channel1
	add hl, bc
	bit SOUND_UNKN_11, [hl]
	jr z, .next
	;
	ld hl, Channel1Field0x23 - Channel1
	add hl, bc
	ld l, [hl]
	ld h, 0
	add hl, de
	ld d, h
	ld e, l
	; get ????
	ld hl, Channel1Field0x24 - Channel1
	add hl, bc
	ld a, [hl]
	; add it to ????
	ld hl, Channel1Field0x25 - Channel1
	add hl, bc
	add [hl]
	ld [hl], a
	ld a, 0
	adc e
	ld e, a
	ld a, 0
	adc d
	ld d, a
	;
	ld hl, Channel1Field0x22 - Channel1
	add hl, bc
	ld a, [hl]
	cp d
	jp c, .quit1
	jr nz, .quit2
	ld hl, Channel1Field0x21 - Channel1
	add hl, bc
	ld a, [hl]
	cp e
	jp c, .quit1
	jr .quit2

.next
	ld a, e
	ld hl, Channel1Field0x23 - Channel1
	add hl, bc
	ld e, [hl]
	sub e
	ld e, a
	ld a, d
	sbc a, 0
	ld d, a
	ld hl, Channel1Field0x24 - Channel1
	add hl, bc
	ld a, [hl]
	add a
	ld [hl], a
	ld a, e
	sbc a, 0
	ld e, a
	ld a, d
	sbc a, 0
	ld d,a
	ld hl, Channel1Field0x22 - Channel1
	add hl, bc
	ld a, d
	cp [hl]
	jr c, .quit1
	jr nz, .quit2
	ld hl, Channel1Field0x21 - Channel1
	add hl, bc
	ld a, e
	cp [hl]
	jr nc, .quit2
.quit1
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	res SOUND_UNKN_09, [hl]
	ld hl, Channel1Flags3 - Channel1
	add hl, bc
	res SOUND_UNKN_11, [hl]
	ret

.quit2
	ld hl, Channel1Frequency - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_UNKN_1, [hl]
	set NOTE_UNKN_0, [hl]
	ret

; e858c

HandleNoise: ; e858c
	; is noise sampling on?
	ld hl, Channel1Flags - Channel1
	add hl, bc
	bit SOUND_NOISE, [hl] ; noise sampling
	ret z
	; are we in a sfx channel?
	ld a, [CurChannel]
	bit 2, a ; sfx
	jr nz, .next
	; is ch8 on? (noise)
	ld hl, Channel8Flags
	bit SOUND_CHANNEL_ON, [hl] ; on?
	jr z, .next
	; is ch8 playing noise?
	bit SOUND_NOISE, [hl]
	ret nz ; quit if so
	;
.next
	ld a, [wNoiseSampleDelay]
	and a
	jr z, ReadNoiseSample
	dec a
	ld [wNoiseSampleDelay], a
	ret

; e85af

ReadNoiseSample: ; e85af
; sample struct:
;	[wx] [yy] [zz]
;	w: ? either 2 or 3
;	x: duration
;	zz: intensity
;       yy: frequency

	; de = [NoiseSampleAddress]
	ld hl, NoiseSampleAddress
	ld e, [hl]
	inc hl
	ld d, [hl]

	; is it empty?
	ld a, e
	or d
	jr z, .quit

	ld a, [de]
	inc de

	cp $ff
	jr z, .quit

	and $f
	inc a
	ld [wNoiseSampleDelay], a
	ld a, [de]
	inc de
	ld [wCurTrackIntensity], a
	ld a, [de]
	inc de
	ld [wCurTrackFrequency], a
	xor a
	ld [wCurTrackFrequency + 1], a

	ld hl, NoiseSampleAddress
	ld [hl], e
	inc hl
	ld [hl], d

	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_UNKN_4, [hl]
	ret

.quit
	ret

; e85e1

ParseMusic: ; e85e1
; parses until a note is read or the song is ended
	call GetMusicByte ; store next byte in a
	cp $ff ; is the song over?
	jr z, .endchannel
	cp $d0 ; is it a note?
	jr c, .readnote
	; then it's a command
.readcommand
	call ParseMusicCommand
	jr ParseMusic ; start over

.readnote
; CurMusicByte contains current note
; special notes
	ld hl, Channel1Flags - Channel1
	add hl, bc
	bit SOUND_SFX, [hl]
	jp nz, Functione8698
	bit SOUND_REST, [hl] ; rest
	jp nz, Functione8698
	bit SOUND_NOISE, [hl] ; noise sample
	jp nz, GetNoiseSample
; normal note
	; set note duration (bottom nybble)
	ld a, [CurMusicByte]
	and $f
	call SetNoteDuration
	; get note pitch (top nybble)
	ld a, [CurMusicByte]
	swap a
	and $f
	jr z, .rest ; pitch 0-> rest
	; update pitch
	ld hl, Channel1Pitch - Channel1
	add hl, bc
	ld [hl], a
	; store pitch in e
	ld e, a
	; store octave in d
	ld hl, Channel1Octave - Channel1
	add hl, bc
	ld d, [hl]
	; update frequency
	call GetFrequency
	ld hl, Channel1Frequency - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	; ????
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_UNKN_4, [hl]
	jp LoadNote



.rest
; note = rest
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_REST, [hl] ; Rest
	ret

;
.endchannel
; $ff is reached in music data
	ld hl, Channel1Flags - Channel1
	add hl, bc
	bit SOUND_SUBROUTINE, [hl] ; in a subroutine?
	jr nz, .readcommand ; execute
	ld a, [CurChannel]
	cp $4 ; channels 0-3?
	jr nc, .chan_5to8
	; ????
	ld hl, Channel5Flags - Channel1
	add hl, bc
	bit SOUND_CHANNEL_ON, [hl]
	jr nz, .ok
.chan_5to8
	ld hl, Channel1Flags - Channel1
	add hl, bc
	bit SOUND_REST, [hl]
	call nz, RestoreVolume
	; end music
	ld a, [CurChannel]
	cp $4 ; channel 5?
	jr nz, .ok
	; ????
	xor a
	ld [rNR10], a ; sweep = 0
.ok
; stop playing
	; turn channel off
	ld hl, Channel1Flags - Channel1
	add hl, bc
	res SOUND_CHANNEL_ON, [hl]
	; note = rest
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_REST, [hl]
	; clear music id & bank
	ld hl, Channel1MusicID - Channel1
	add hl, bc
	xor a
	ld [hli], a ; id hi
	ld [hli], a ; id lo
	ld [hli], a ; bank
	ret

; e8679

RestoreVolume: ; e8679
	; ch5 only
	ld a, [CurChannel]
	cp $4
	ret nz
	xor a
	ld hl, Channel6CryPitch
	ld [hli], a
	ld [hl], a
	ld hl, Channel8CryPitch
	ld [hli], a
	ld [hl], a
	ld a, [LastVolume]
	ld [Volume], a
	xor a
	ld [LastVolume], a
	ld [SFXPriority], a
	ret

; e8698

Functione8698: ; e8698
	; turn noise sampling on
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_UNKN_4, [hl] ; noise sample
	; update note duration
	ld a, [CurMusicByte]
	call SetNoteDuration ; top nybble doesnt matter?
	; update intensity from next param
	call GetMusicByte
	ld hl, Channel1Intensity - Channel1
	add hl, bc
	ld [hl], a
	; update lo frequency from next param
	call GetMusicByte
	ld hl, Channel1FrequencyLo - Channel1
	add hl, bc
	ld [hl], a
	; are we on the last channel? (noise sampling)
	ld a, [CurChannel]
	and $3
	cp $3
	ret z
	; update hi frequency from next param
	call GetMusicByte
	ld hl, Channel1FrequencyHi - Channel1
	add hl, bc
	ld [hl], a
	ret

; e86c5

GetNoiseSample: ; e86c5
; load ptr to sample header in NoiseSampleAddress
	; are we on the last channel?
	ld a, [CurChannel]
	and $3
	cp $3
	; ret if not
	ret nz
	; update note duration
	ld a, [CurMusicByte]
	and $f
	call SetNoteDuration
	; check current channel
	ld a, [CurChannel]
	bit 2, a ; are we in a sfx channel?
	jr nz, .sfx
	ld hl, Channel8Flags
	bit SOUND_CHANNEL_ON, [hl] ; is ch8 on? (noise)
	ret nz
	ld a, [MusicNoiseSampleSet]
	jr .next

.sfx
	ld a, [SFXNoiseSampleSet]
.next
	; load noise sample set id into de
	ld e, a
	ld d, 0
	; load ptr to noise sample set in hl
	ld hl, Drumkits
rept 2
	add hl, de
endr
	ld a, [hli]
	ld h, [hl]
	ld l, a
	; get pitch
	ld a, [CurMusicByte]
	swap a
	; non-rest note?
	and $f
	ret z
	; use 'pitch' to seek noise sample set
	ld e, a
	ld d, 0
rept 2
	add hl, de
endr
	; load sample pointer into NoiseSampleAddress
	ld a, [hli]
	ld [NoiseSampleAddressLo], a
	ld a, [hl]
	ld [NoiseSampleAddressHi], a
	; clear ????
	xor a
	ld [wNoiseSampleDelay], a
	ret

; e870f

ParseMusicCommand: ; e870f
	; reload command
	ld a, [CurMusicByte]
	; get command #
	sub a, $d0 ; first command
	ld e, a
	ld d, 0
	; seek command pointer
	ld hl, MusicCommands
rept 2
	add hl, de
endr
	; jump to the new pointer
	ld a, [hli]
	ld h, [hl]
	ld l, a
	jp [hl]

; e8720

MusicCommands: ; e8720
; pointer to each command in order
	; octaves
	dw Music_Octave8 ; octave 8
	dw Music_Octave7 ; octave 7
	dw Music_Octave6 ; octave 6
	dw Music_Octave5 ; octave 5
	dw Music_Octave4 ; octave 4
	dw Music_Octave3 ; octave 3
	dw Music_Octave2 ; octave 2
	dw Music_Octave1 ; octave 1
	dw Music_NoteType ; note length + intensity
	dw Music_ForceOctave ; set starting octave
	dw Music_Tempo ; tempo
	dw Music_DutyCycle ; duty cycle
	dw Music_Intensity ; intensity
	dw Music_SoundStatus ; update sound status
	dw MusicDE ; ???? + duty cycle
	dw Music_ToggleSFX ;
	dw MusicE0 ;
	dw Music_Vibrato ; vibrato
	dw MusicE2 ; unused
	dw Music_ToggleNoise ; music noise sampling
	dw Music_Panning ; force panning
	dw Music_Volume ; volume
	dw Music_Tone ; tune
	dw MusicE7 ; unused
	dw MusicE8 ; unused
	dw Music_TempoRelative ; global tempo
	dw Music_RestartChannel ; restart current channel from header
	dw Music_NewSong ; new song
	dw Music_SFXPriorityOn ; sfx priority on
	dw Music_SFXPriorityOff ; sfx priority off
	dw MusicEE ; unused
	dw Music_StereoPanning ; stereo panning
	dw Music_SFXToggleNoise ; sfx noise sampling
	dw MusicF1 ; nothing
	dw MusicF2 ; nothing
	dw MusicF3 ; nothing
	dw MusicF4 ; nothing
	dw MusicF5 ; nothing
	dw MusicF6 ; nothing
	dw MusicF7 ; nothing
	dw MusicF8 ; nothing
	dw MusicF9 ; unused
	dw Music_SetCondition ;
	dw Music_JumpIf ;
	dw Music_JumpChannel ; jump
	dw Music_LoopChannel ; loop
	dw Music_CallChannel ; call
	dw Music_EndChannel ; return
; e8780

MusicF1: ; e8780
MusicF2: ; e8780
MusicF3: ; e8780
MusicF4: ; e8780
MusicF5: ; e8780
MusicF6: ; e8780
MusicF7: ; e8780
MusicF8: ; e8780
	ret

; e8781

Music_EndChannel: ; e8781
; called when $ff is encountered w/ subroutine flag set
; end music stream
; return to caller of the subroutine
	; reset subroutine flag
	ld hl, Channel1Flags - Channel1
	add hl, bc
	res SOUND_SUBROUTINE, [hl]
	; copy LastMusicAddress to MusicAddress
	ld hl, Channel1LastMusicAddress - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	ret

; e8796

Music_CallChannel: ; e8796
; call music stream (subroutine)
; parameters: ll hh ; pointer to subroutine
	; get pointer from next 2 bytes
	call GetMusicByte
	ld e, a
	call GetMusicByte
	ld d, a
	push de
	; copy MusicAddress to LastMusicAddress
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	ld hl, Channel1LastMusicAddress - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	; load pointer into MusicAddress
	pop de
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	; set subroutine flag
	ld hl, Channel1Flags - Channel1
	add hl, bc
	set SOUND_SUBROUTINE, [hl]
	ret

; e87bc

Music_JumpChannel: ; e87bc
; jump
; parameters: ll hh ; pointer
	; get pointer from next 2 bytes
	call GetMusicByte
	ld e, a
	call GetMusicByte
	ld d, a
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	ret

; e87cc

Music_LoopChannel: ; e87cc
; loops xx - 1 times
; 	00: infinite
; params: 3
;	xx ll hh
;		xx : loop count
;   	ll hh : pointer

	; get loop count
	call GetMusicByte
	ld hl, Channel1Flags - Channel1
	add hl, bc
	bit SOUND_LOOPING, [hl] ; has the loop been initiated?
	jr nz, .checkloop
	and a ; loop counter 0 = infinite
	jr z, .loop
	; initiate loop
	dec a
	set SOUND_LOOPING, [hl] ; set loop flag
	ld hl, Channel1LoopCount - Channel1
	add hl, bc
	ld [hl], a ; store loop counter
.checkloop
	ld hl, Channel1LoopCount - Channel1
	add hl, bc
	ld a, [hl]
	and a ; are we done?
	jr z, .endloop
	dec [hl]
.loop
	; get pointer
	call GetMusicByte
	ld e, a
	call GetMusicByte
	ld d, a
	; load new pointer into MusicAddress
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	ret

.endloop
	; reset loop flag
	ld hl, Channel1Flags - Channel1
	add hl, bc
	res SOUND_LOOPING, [hl]
	; skip to next command
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	inc de ; skip
	inc de ; pointer
	ld [hl], d
	dec hl
	ld [hl], e
	ret

; e880e

Music_SetCondition: ; e880e
; set condition for a jump
; used with FB
; params: 1
;	xx ; condition

	; set condition
	call GetMusicByte
	ld hl, Channel1Condition - Channel1
	add hl, bc
	ld [hl], a
	ret

; e8817

Music_JumpIf: ; e8817
; conditional jump
; used with FA
; params: 3
; 	xx: condition
;	ll hh: pointer

; check condition
	; a = condition
	call GetMusicByte
	; if existing condition matches, jump to new address
	ld hl, Channel1Condition - Channel1
	add hl, bc
	cp [hl]
	jr z, .jump
; skip to next command
	; get address
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	; skip pointer
rept 2
	inc de
endr
	; update address
	ld [hl], d
	dec hl
	ld [hl], e
	ret

.jump
; jump to the new address
	; get pointer
	call GetMusicByte
	ld e, a
	call GetMusicByte
	ld d, a
	; update pointer in MusicAddress
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	ret

; e883e

MusicEE; e883e
; conditional jump
; checks a byte in ram corresponding to the current channel
; doesn't seem to be set by any commands
; params: 2
;		ll hh ; pointer

; if ????, jump
	; get channel
	ld a, [CurChannel]
	and $3 ; ch0-3
	ld e, a
	ld d, 0
	; hl = Channel1JumpCondition + channel id
	ld hl, Channel1JumpCondition
	add hl, de
	; if set, jump
	ld a, [hl]
	and a
	jr nz, .jump
; skip to next command
	; get address
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	; skip pointer
rept 2
	inc de
endr
	; update address
	ld [hl], d
	dec hl
	ld [hl], e
	ret

.jump
	; reset jump flag
	ld [hl], 0
	; de = pointer
	call GetMusicByte
	ld e, a
	call GetMusicByte
	ld d, a
	; update address
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	ret

; e886d

MusicF9: ; e886d
; sets some flag
; seems to be unused
; params: 0
	ld a, 1
	ld [wc2b5], a
	ret

; e8873

MusicE2: ; e8873
; seems to have been dummied out
; params: 1
	call GetMusicByte
	ld hl, Channel1Field0x2c - Channel1
	add hl, bc
	ld [hl], a
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	set SOUND_UNKN_0B, [hl]
	ret

; e8882

Music_Vibrato: ; e8882
; vibrato
; params: 2
;	1: [xx]
	; delay in frames
;	2: [yz]
	; y: extent
	; z: rate (# frames per cycle)

	; set vibrato flag?
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	set SOUND_VIBRATO, [hl]
	; start at lower frequency (extent is positive)
	ld hl, Channel1Flags3 - Channel1
	add hl, bc
	res SOUND_VIBRATO_DIR, [hl]
	; get delay
	call GetMusicByte
; update delay
	ld hl, Channel1VibratoDelay - Channel1
	add hl, bc
	ld [hl], a
; update delay count
	ld hl, Channel1VibratoDelayCount - Channel1
	add hl, bc
	ld [hl], a
; update extent
; this is split into halves only to get added back together at the last second
	; get extent/rate
	call GetMusicByte
	ld hl, Channel1VibratoExtent - Channel1
	add hl, bc
	ld d, a
	; get top nybble
	and $f0
	swap a
	srl a ; halve
	ld e, a
	adc a, 0; round up
	swap a
	or e
	ld [hl], a
; update rate
	ld hl, Channel1VibratoRate - Channel1
	add hl, bc
	; get bottom nybble
	ld a, d
	and $f
	ld d, a
	swap a
	or d
	ld [hl], a
	ret

; e88bd

MusicE0: ; e88bd
; ????
; params: 2
	call GetMusicByte
	ld [wc297], a

	call GetMusicByte
	ld d, a
	and $f
	ld e, a

	ld a, d
	swap a
	and $f
	ld d, a
	call GetFrequency
	ld hl, Channel1Field0x21 - Channel1
	add hl, bc
	ld [hl], e
	ld hl, Channel1Field0x22 - Channel1
	add hl, bc
	ld [hl], d
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	set SOUND_UNKN_09, [hl]
	ret

; e88e4

Music_Tone: ; e88e4
; tone
; params: 2
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	set SOUND_CRY_PITCH, [hl]
	ld hl, Channel1CryPitch + 1 - Channel1
	add hl, bc
	call GetMusicByte
	ld [hld], a
	call GetMusicByte
	ld [hl], a
	ret

; e88f7

MusicE7: ; e88f7
; unused
; params: 1
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	set SOUND_UNKN_0E, [hl]
	call GetMusicByte
	ld hl, Channel1Field0x29 - Channel1
	add hl, bc
	ld [hl], a
	ret

; e8906

MusicDE: ; e8906
; ???? + duty cycle
; params: 1
	;
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	set SOUND_DUTY, [hl] ; duty cycle
	;
	call GetMusicByte
	rrca
	rrca
	ld hl, Channel1Field0x1c - Channel1
	add hl, bc
	ld [hl], a
	; update duty cycle
	and $c0 ; only uses top 2 bits
	ld hl, Channel1DutyCycle - Channel1
	add hl, bc
	ld [hl], a
	ret

; e891e

MusicE8: ; e891e
; unused
; params: 1
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	set SOUND_UNKN_0D, [hl]
	call GetMusicByte
	ld hl, Channel1Field0x2a - Channel1
	add hl, bc
	ld [hl], a
	ret

; e892d

Music_ToggleSFX: ; e892d
; toggle something
; params: none
	ld hl, Channel1Flags - Channel1
	add hl, bc
	bit SOUND_SFX, [hl]
	jr z, .on
	res SOUND_SFX, [hl]
	ret

.on
	set SOUND_SFX, [hl]
	ret

; e893b

Music_ToggleNoise: ; e893b
; toggle music noise sampling
; can't be used as a straight toggle since the param is not read from on->off
; params:
; 	noise on: 1
; 	noise off: 0
	; check if noise sampling is on
	ld hl, Channel1Flags - Channel1
	add hl, bc
	bit SOUND_NOISE, [hl]
	jr z, .on
	; turn noise sampling off
	res SOUND_NOISE, [hl]
	ret

.on
	; turn noise sampling on
	set SOUND_NOISE, [hl]
	call GetMusicByte
	ld [MusicNoiseSampleSet], a
	ret

; e894f

Music_SFXToggleNoise: ; e894f
; toggle sfx noise sampling
; params:
;	on: 1
; 	off: 0
	; check if noise sampling is on
	ld hl, Channel1Flags - Channel1
	add hl, bc
	bit SOUND_NOISE, [hl]
	jr z, .on
	; turn noise sampling off
	res SOUND_NOISE, [hl]
	ret

.on
	; turn noise sampling on
	set SOUND_NOISE, [hl]
	call GetMusicByte
	ld [SFXNoiseSampleSet], a
	ret

; e8963

Music_NoteType: ; e8963
; note length
;	# frames per 16th note
; intensity: see Music_Intensity
; params: 2
	; note length
	call GetMusicByte
	ld hl, Channel1NoteLength - Channel1
	add hl, bc
	ld [hl], a
	ld a, [CurChannel]
	and $3
	cp CHAN4 ; CHAN8 & $3
	ret z
	; intensity
	call Music_Intensity
	ret

; e8977

Music_SoundStatus: ; e8977
; update sound status
; params: 1
	call GetMusicByte
	ld [SoundInput], a
	ld hl, Channel1NoteFlags - Channel1
	add hl, bc
	set NOTE_UNKN_3, [hl]
	ret

; e8984

Music_DutyCycle: ; e8984
; duty cycle
; params: 1
	call GetMusicByte
	rrca
	rrca
	and $c0
	ld hl, Channel1DutyCycle - Channel1
	add hl, bc
	ld [hl], a
	ret

; e8991

Music_Intensity: ; e8991
; intensity
; params: 1
;	hi: pressure
;   lo: velocity
	call GetMusicByte
	ld hl, Channel1Intensity - Channel1
	add hl, bc
	ld [hl], a
	ret

; e899a

Music_Tempo: ; e899a
; global tempo
; params: 2
;	de: tempo
	call GetMusicByte
	ld d, a
	call GetMusicByte
	ld e, a
	call SetGlobalTempo
	ret

; e89a6

Music_Octave8: ; e89a6
Music_Octave7: ; e89a6
Music_Octave6: ; e89a6
Music_Octave5: ; e89a6
Music_Octave4: ; e89a6
Music_Octave3: ; e89a6
Music_Octave2: ; e89a6
Music_Octave1: ; e89a6
; set octave based on lo nybble of the command
	ld hl, Channel1Octave - Channel1
	add hl, bc
	ld a, [CurMusicByte]
	and 7
	ld [hl], a
	ret

; e89b1

Music_ForceOctave: ; e89b1
; set starting octave
; this forces all notes up by the starting octave
; params: 1
	call GetMusicByte
	ld hl, Channel1StartingOctave - Channel1
	add hl, bc
	ld [hl], a
	ret

; e89ba

Music_StereoPanning: ; e89ba
; stereo panning
; params: 1
	; stereo on?
	ld a, [Options]
	bit 5, a ; stereo
	jr nz, Music_Panning
	; skip param
	call GetMusicByte
	ret

; e89c5

Music_Panning: ; e89c5
; force panning
; params: 1
	call SetLRTracks
	call GetMusicByte
	ld hl, Channel1Tracks - Channel1
	add hl, bc
	and [hl]
	ld [hl], a
	ret

; e89d2

Music_Volume: ; e89d2
; set volume
; params: 1
;	see Volume
	; read param even if it's not used
	call GetMusicByte
	; is the song fading?
	ld a, [MusicFade]
	and a
	ret nz
	; reload param
	ld a, [CurMusicByte]
	; set volume
	ld [Volume], a
	ret

; e89e1

Music_TempoRelative: ; e89e1
; set global tempo to current channel tempo +- param
; params: 1 signed
	call GetMusicByte
	ld e, a
	; check sign
	cp $80
	jr nc, .negative
;positive
	ld d, 0
	jr .ok

.negative
	ld d, -1
.ok
	ld hl, Channel1Tempo - Channel1
	add hl, bc
	ld a, [hli]
	ld h, [hl]
	ld l, a
	add hl, de
	ld e, l
	ld d, h
	call SetGlobalTempo
	ret

; e89fd

Music_SFXPriorityOn: ; e89fd
; turn sfx priority on
; params: none
	ld a, 1
	ld [SFXPriority], a
	ret

; e8a03

Music_SFXPriorityOff: ; e8a03
; turn sfx priority off
; params: none
	xor a
	ld [SFXPriority], a
	ret

; e8a08

Music_RestartChannel: ; e8a08
; restart current channel from channel header (same bank)
; params: 2 (5)
; ll hh: pointer to new channel header
;	header format: 0x yy zz
;		x: channel # (0-3)
;		zzyy: pointer to new music data

	; update music id
	ld hl, Channel1MusicID - Channel1
	add hl, bc
	ld a, [hli]
	ld [MusicIDLo], a
	ld a, [hl]
	ld [MusicIDHi], a
	; update music bank
	ld hl, Channel1MusicBank - Channel1
	add hl, bc
	ld a, [hl]
	ld [MusicBank], a
	; get pointer to new channel header
	call GetMusicByte
	ld l, a
	call GetMusicByte
	ld h, a
	ld e, [hl]
	inc hl
	ld d, [hl]
	push bc ; save current channel
	call LoadChannel
	call StartChannel
	pop bc ; restore current channel
	ret

; e8a30

Music_NewSong: ; e8a30
; new song
; params: 2
;	de: song id
	call GetMusicByte
	ld e, a
	call GetMusicByte
	ld d, a
	push bc
	call _PlayMusic
	pop bc
	ret

; e8a3e

GetMusicByte: ; e8a3e
; returns byte from current address in a
; advances to next byte in music data
; input: bc = start of current channel
	push hl
	push de
	; load address into de
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld a, [hli]
	ld e, a
	ld d, [hl]
	; load bank into a
	ld hl, Channel1MusicBank - Channel1
	add hl, bc
	ld a, [hl]
	; get byte
	call _LoadMusicByte ; load data into CurMusicByte
	inc de ; advance to next byte for next time this is called
	; update channeldata address
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	ld a, e
	ld [hli], a
	ld [hl], d
	; cleanup
	pop de
	pop hl
	; store channeldata in a
	ld a, [CurMusicByte]
	ret

; e8a5d

GetFrequency: ; e8a5d
; generate frequency
; input:
; 	d: octave
;	e: pitch
; output:
; 	de: frequency

; get octave
	; get starting octave
	ld hl, Channel1StartingOctave - Channel1
	add hl, bc
	ld a, [hl]
	swap a ; hi nybble
	and $f
	; add current octave
	add d
	push af ; we'll use this later
	; get starting octave
	ld hl, Channel1StartingOctave - Channel1
	add hl, bc
	ld a, [hl]
	and $f ; lo nybble
	;
	ld l, a ; ok
	ld d, 0
	ld h, d
	add hl, de ; add current pitch
	add hl, hl ; skip 2 bytes for each
	ld de, FrequencyTable
	add hl, de
	ld e, [hl]
	inc hl
	ld d, [hl]
	; get our octave
	pop af
	; shift right by [7 - octave] bits
.loop
	; [7 - octave] loops
	cp $7
	jr nc, .ok
	; sra de
	sra d
	rr e
	inc a
	jr .loop

.ok
	ld a, d
	and $7 ; top 3 bits for frequency (11 total)
	ld d, a
	ret

; e8a8d

SetNoteDuration: ; e8a8d
; input: a = note duration in 16ths
	; store delay units in de
	inc a
	ld e, a
	ld d, 0
	; store NoteLength in a
	ld hl, Channel1NoteLength - Channel1
	add hl, bc
	ld a, [hl]
	; multiply NoteLength by delay units
	ld l, 0; just multiply
	call .Multiply
	ld a, l ; % $100
	; store Tempo in de
	ld hl, Channel1Tempo - Channel1
	add hl, bc
	ld e, [hl]
	inc hl
	ld d, [hl]
	; add ???? to the next result
	ld hl, Channel1Field0x16 - Channel1
	add hl, bc
	ld l, [hl]
	; multiply Tempo by last result (NoteLength * delay % $100)
	call .Multiply
	; copy result to de
	ld e, l
	ld d, h
	; store result in ????
	ld hl, Channel1Field0x16 - Channel1
	add hl, bc
	ld [hl], e
	; store result in NoteDuration
	ld hl, Channel1NoteDuration - Channel1
	add hl, bc
	ld [hl], d
	ret

; e8ab8

.Multiply: ; e8ab8
; multiplies a and de
; adds the result to l
; stores the result in hl
	ld h, 0
.loop
	; halve a
	srl a
	; is there a remainder?
	jr nc, .skip
	; add it to the result
	add hl, de
.skip
	; add de, de
	sla e
	rl d
	; are we done?
	and a
	jr nz, .loop
	ret

; e8ac7

SetGlobalTempo: ; e8ac7
	push bc ; save current channel
	; are we dealing with music or sfx?
	ld a, [CurChannel]
	cp CHAN5
	jr nc, .sfxchannels
	ld bc, Channel1
	call Tempo
	ld bc, Channel2
	call Tempo
	ld bc, Channel3
	call Tempo
	ld bc, Channel4
	call Tempo
	jr .end

.sfxchannels
	ld bc, Channel5
	call Tempo
	ld bc, Channel6
	call Tempo
	ld bc, Channel7
	call Tempo
	ld bc, Channel8
	call Tempo
.end
	pop bc ; restore current channel
	ret

; e8b03

Tempo: ; e8b03
; input:
; 	de: note length
	; update Tempo
	ld hl, Channel1Tempo - Channel1
	add hl, bc
	ld [hl], e
	inc hl
	ld [hl], d
	; clear ????
	xor a
	ld hl, Channel1Field0x16 - Channel1
	add hl, bc
	ld [hl], a
	ret

; e8b11

StartChannel: ; e8b11
	call SetLRTracks
	ld hl, Channel1Flags - Channel1
	add hl, bc
	set SOUND_CHANNEL_ON, [hl] ; turn channel on
	ret

; e8b1b

SetLRTracks: ; e8b1b
; set tracks for a the current channel to default
; seems to be redundant since this is overwritten by stereo data later
	push de
	; store current channel in de
	ld a, [CurChannel]
	and $3
	ld e, a
	ld d, 0
	; get this channel's lr tracks
	call GetLRTracks
	add hl, de ; de = channel 0-3
	ld a, [hl]
	; load lr tracks into Tracks
	ld hl, Channel1Tracks - Channel1
	add hl, bc
	ld [hl], a
	pop de
	ret

; e8b30

_PlayMusic:: ; e8b30
; load music
	call MusicOff
	ld hl, MusicID
	ld [hl], e ; song number
	inc hl
	ld [hl], d ; MusicIDHi (always $)
	ld hl, Music
	add hl, de ; three
	add hl, de ; byte
	add hl, de ; pointer
	ld a, [hli]
	ld [MusicBank], a
	ld e, [hl]
	inc hl
	ld d, [hl] ; music header address
	call LoadMusicByte ; store first byte of music header in a
	rlca
	rlca
	and $3 ; get number of channels
	inc a
.loop
; start playing channels
	push af
	call LoadChannel
	call StartChannel
	pop af
	dec a
	jr nz, .loop
	xor a
	ld [wc2b5], a
	ld [Channel1JumpCondition], a
	ld [Channel2JumpCondition], a
	ld [Channel3JumpCondition], a
	ld [Channel4JumpCondition], a
	ld [NoiseSampleAddressLo], a
	ld [NoiseSampleAddressHi], a
	ld [wNoiseSampleDelay], a
	ld [MusicNoiseSampleSet], a
	call MusicOn
	ret

; e8b79

_PlayCryHeader:: ; e8b79
; Play cry de using parameters:
;	CryPitch
;	CryLength
	
	call MusicOff
	
; Overload the music id with the cry id
	ld hl, MusicID
	ld [hl], e
	inc hl
	ld [hl], d
	
; 3-byte pointers (bank, address)
	ld hl, Cries
rept 3
	add hl, de
endr
	
	ld a, [hli]
	ld [MusicBank], a
	
	ld e, [hl]
	inc hl
	ld d, [hl]
	
; Read the cry's sound header
	call LoadMusicByte
	; Top 2 bits contain the number of channels
	rlca
	rlca
	and 3
	
; For each channel:
	inc a
.loop
	push af
	call LoadChannel
	
	ld hl, Channel1Flags - Channel1
	add hl, bc
	set SOUND_REST, [hl]
	
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	set SOUND_CRY_PITCH, [hl]
	
	ld hl, Channel1CryPitch - Channel1
	add hl, bc
	ld a, [CryPitch]
	ld [hli], a
	ld a, [CryPitch + 1]
	ld [hl], a
	
; No tempo for channel 4
	ld a, [CurChannel]
	and 3
	cp 3
	jr nc, .start
	
; Tempo is effectively length
	ld hl, Channel1Tempo - Channel1
	add hl, bc
	ld a, [CryLength]
	ld [hli], a
	ld a, [CryLength+1]
	ld [hl], a
.start
	call StartChannel
	ld a, [wStereoPanningMask]
	and a
	jr z, .next
	
; Stereo only: Play cry from the monster's side.
; This only applies in-battle.
	
	ld a, [Options]
	bit 5, a ; stereo
	jr z, .next
	
; [Tracks] &= [CryTracks]
	ld hl, Channel1Tracks - Channel1
	add hl, bc
	ld a, [hl]
	ld hl, CryTracks
	and [hl]
	ld hl, Channel1Tracks - Channel1
	add hl, bc
	ld [hl], a
	
.next
	pop af
	dec a
	jr nz, .loop
	
	
; Cries play at max volume, so we save the current volume for later.
	ld a, [LastVolume]
	and a
	jr nz, .end
	
	ld a, [Volume]
	ld [LastVolume], a
	ld a, $77
	ld [Volume], a
	
.end
	ld a, 1 ; stop playing music
	ld [SFXPriority], a
	call MusicOn
	ret

; e8c04

_PlaySFX:: ; e8c04
; clear channels if they aren't already
	call MusicOff
	ld hl, Channel5Flags
	bit SOUND_CHANNEL_ON, [hl] ; ch5 on?
	jr z, .ch6
	res SOUND_CHANNEL_ON, [hl] ; turn it off
	xor a
	ld [rNR11], a ; length/wavepattern = 0
	ld a, $8
	ld [rNR12], a ; envelope = 0
	xor a
	ld [rNR13], a ; frequency lo = 0
	ld a, $80
	ld [rNR14], a ; restart sound (freq hi = 0)
	xor a
	ld [SoundInput], a ; global sound off
	ld [rNR10], a ; sweep = 0
.ch6
	ld hl, Channel6Flags
	bit SOUND_CHANNEL_ON, [hl]
	jr z, .ch7
	res SOUND_CHANNEL_ON, [hl] ; turn it off
	xor a
	ld [rNR21], a ; length/wavepattern = 0
	ld a, $8
	ld [rNR22], a ; envelope = 0
	xor a
	ld [rNR23], a ; frequency lo = 0
	ld a, $80
	ld [rNR24], a ; restart sound (freq hi = 0)
.ch7
	ld hl, Channel7Flags
	bit SOUND_CHANNEL_ON, [hl]
	jr z, .ch8
	res SOUND_CHANNEL_ON, [hl] ; turn it off
	xor a
	ld [rNR30], a ; sound mode #3 off
	ld [rNR31], a ; length/wavepattern = 0
	ld a, $8
	ld [rNR32], a ; envelope = 0
	xor a
	ld [rNR33], a ; frequency lo = 0
	ld a, $80
	ld [rNR34], a ; restart sound (freq hi = 0)
.ch8
	ld hl, Channel8Flags
	bit SOUND_CHANNEL_ON, [hl]
	jr z, .chscleared
	res SOUND_CHANNEL_ON, [hl] ; turn it off
	xor a
	ld [rNR41], a ; length/wavepattern = 0
	ld a, $8
	ld [rNR42], a ; envelope = 0
	xor a
	ld [rNR43], a ; frequency lo = 0
	ld a, $80
	ld [rNR44], a ; restart sound (freq hi = 0)
	xor a
	ld [NoiseSampleAddressLo], a
	ld [NoiseSampleAddressHi], a
.chscleared
; start reading sfx header for # chs
	ld hl, MusicID
	ld [hl], e
	inc hl
	ld [hl], d
	ld hl, SFX
	add hl, de ; three
	add hl, de ; byte
	add hl, de ; pointers
	; get bank
	ld a, [hli]
	ld [MusicBank], a
	; get address
	ld e, [hl]
	inc hl
	ld d, [hl]
	; get # channels
	call LoadMusicByte
	rlca ; top 2
	rlca ; bits
	and $3
	inc a ; # channels -> # loops
.startchannels
	push af
	call LoadChannel ; bc = current channel
	ld hl, Channel1Flags - Channel1
	add hl, bc
	set SOUND_SFX, [hl]
	call StartChannel
	pop af
	dec a
	jr nz, .startchannels
	call MusicOn
	xor a
	ld [SFXPriority], a
	ret

; e8ca6


PlayStereoSFX:: ; e8ca6
; play sfx de

	call MusicOff
	
; standard procedure if stereo's off
	ld a, [Options]
	bit 5, a
	jp z, _PlaySFX
	
; else, let's go ahead with this
	ld hl, MusicID
	ld [hl], e
	inc hl
	ld [hl], d
	
; get sfx ptr
	ld hl, SFX
rept 3
	add hl, de
endr
	
; bank
	ld a, [hli]
	ld [MusicBank], a
; address
	ld e, [hl]
	inc hl
	ld d, [hl]
	
; bit 2-3
	call LoadMusicByte
	rlca
	rlca
	and 3 ; ch1-4
	inc a
	
.loop
	push af
	call LoadChannel
	
	ld hl, Channel1Flags - Channel1
	add hl, bc
	set SOUND_SFX, [hl]
	
	push de
	; get tracks for this channel
	ld a, [CurChannel]
	and 3 ; ch1-4
	ld e, a
	ld d, 0
	call GetLRTracks
	add hl, de
	ld a, [hl]
	ld hl, wStereoPanningMask
	and [hl]
	
	ld hl, Channel1Tracks - Channel1
	add hl, bc
	ld [hl], a
	
	ld hl, Channel1Field0x30 - Channel1 ; $c131 - Channel1
	add hl, bc
	ld [hl], a
	
	ld a, [CryTracks]
	cp 2 ; ch 1-2
	jr c, .skip
	
; ch3-4
	ld a, [wSFXDuration]
	
	ld hl, Channel1Field0x2e - Channel1 ; $c12f - Channel1
	add hl, bc
	ld [hl], a
	
	ld hl, Channel1Field0x2f - Channel1 ; $c130 - Channel1
	add hl, bc
	ld [hl], a
	
	ld hl, Channel1Flags2 - Channel1
	add hl, bc
	set SOUND_UNKN_0F, [hl]
	
.skip
	pop de
	
; turn channel on
	ld hl, Channel1Flags - Channel1
	add hl, bc
	set SOUND_CHANNEL_ON, [hl] ; on
	
; done?
	pop af
	dec a
	jr nz, .loop
	
; we're done
	call MusicOn
	ret

; e8d1b


LoadChannel: ; e8d1b
; prep channel for use
; input:
; 	de:
	; get pointer to current channel
	call LoadMusicByte
	inc de
	and $7 ; bit 0-2 (current channel)
	ld [CurChannel], a
	ld c, a
	ld b, 0
	ld hl, ChannelPointers
rept 2
	add hl, bc
endr
	ld c, [hl]
	inc hl
	ld b, [hl] ; bc = channel pointer
	ld hl, Channel1Flags - Channel1
	add hl, bc
	res SOUND_CHANNEL_ON, [hl] ; channel off
	call ChannelInit
	; load music pointer
	ld hl, Channel1MusicAddress - Channel1
	add hl, bc
	call LoadMusicByte
	ld [hli], a
	inc de
	call LoadMusicByte
	ld [hl], a
	inc de
	; load music id
	ld hl, Channel1MusicID - Channel1
	add hl, bc
	ld a, [MusicIDLo]
	ld [hli], a
	ld a, [MusicIDHi]
	ld [hl], a
	; load music bank
	ld hl, Channel1MusicBank - Channel1
	add hl, bc
	ld a, [MusicBank]
	ld [hl], a
	ret

; e8d5b

ChannelInit: ; e8d5b
; make sure channel is cleared
; set default tempo and note length in case nothing is loaded
; input:
;   bc = channel struct pointer
	push de
	xor a
	; get channel struct location and length
	ld hl, Channel1MusicID - Channel1 ; start
	add hl, bc
	ld e, Channel2 - Channel1 ; channel struct length
	; clear channel
.loop
	ld [hli], a
	dec e
	jr nz, .loop
	; set tempo to default ($100)
	ld hl, Channel1Tempo - Channel1
	add hl, bc
	xor a
	ld [hli], a
	inc a
	ld [hl], a
	; set note length to default ($1) (fast)
	ld hl, Channel1NoteLength - Channel1
	add hl, bc
	ld [hl], a
	pop de
	ret

; e8d76

LoadMusicByte:: ; e8d76
; input:
;   de = current music address
; output:
;   a = CurMusicByte
	ld a, [MusicBank]
	call _LoadMusicByte
	ld a, [CurMusicByte]
	ret

; e8d80

FrequencyTable: ; e8d80
	dw 0 ; filler
	dw $f82c
	dw $f89d
	dw $f907
	dw $f96b
	dw $f9ca
	dw $fa23
	dw $fa77
	dw $fac7
	dw $fb12
	dw $fb58
	dw $fb9b
	dw $fbda
	dw $fc16
	dw $fc4e
	dw $fc83
	dw $fcb5
	dw $fce5
	dw $fd11
	dw $fd3b
	dw $fd63
	dw $fd89
	dw $fdac
	dw $fdcd
	dw $fded
; e8db2

WaveSamples: ; e8db2
	; these are streams of 32 4-bit values used as wavepatterns
	; nothing interesting here!
	dn 0, 2, 4, 6, 8, 10, 12, 14, 15, 15, 15, 14, 14, 13, 13, 12, 12, 11, 10, 9, 8, 7, 6, 5, 4, 4, 3, 3, 2, 2, 1, 1
	dn 0, 2, 4, 6, 8, 10, 12, 14, 14, 15, 15, 15, 15, 14, 14, 14, 13, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 2, 1, 1
	dn 1, 3, 6, 9, 11, 13, 14, 14, 14, 14, 15, 15, 15, 15, 14, 13, 13, 14, 15, 15, 15, 15, 14, 14, 14, 14, 13, 11, 9, 6, 3, 1
	dn 0, 2, 4, 6, 8, 10, 12, 13, 14, 15, 15, 14, 13, 14, 15, 15, 14, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0
	dn 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 13, 14, 14, 15, 7, 7, 15, 14, 14, 13, 12, 10, 8, 7, 6, 5, 4, 3, 2, 1, 0
	dn 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 3, 3, 2, 2, 1, 1, 15, 15, 14, 14, 12, 12, 10, 10, 8, 8, 10, 10, 12, 12, 14, 14
	dn 0, 2, 4, 6, 8, 10, 12, 14, 12, 11, 10, 9, 8, 7, 6, 5, 15, 15, 15, 14, 14, 13, 13, 12, 4, 4, 3, 3, 2, 2, 1, 1
	dn 12, 0, 10, 9, 8, 7, 15, 5, 15, 15, 15, 14, 14, 13, 13, 12, 4, 4, 3, 3, 2, 2, 15, 1, 0, 2, 4, 6, 8, 10, 12, 14
	dn 4, 4, 3, 3, 2, 2, 1, 15, 0, 0, 4, 6, 8, 10, 12, 14, 15, 8, 15, 14, 14, 13, 13, 12, 12, 11, 10, 9, 8, 7, 6, 5
	dn 1, 1, 0, 0, 0, 0, 0, 8, 0, 0, 1, 3, 5, 7, 9, 10, 11, 4, 11, 10, 10, 9, 9, 8, 8, 7, 6, 5, 4, 3, 2, 1
; e8e52

Drumkits: ; e8e52
	dw Drumkit0
	dw Drumkit1
	dw Drumkit2
	dw Drumkit3
	dw Drumkit4
	dw Drumkit5
; e8e5e

Drumkit0: ; e8e5e
	dw Drum00    ; rest
	dw Snare1    ; c
	dw Snare2    ; c#
	dw Snare3    ; d
	dw Snare4    ; d#
	dw Drum05    ; e
	dw Triangle1 ; f
	dw Triangle2 ; f#
	dw HiHat1    ; g
	dw Snare5    ; g#
	dw Snare6    ; a
	dw Snare7    ; a#
	dw HiHat2    ; b
Drumkit1: ; e8e78
	dw Drum00
	dw HiHat1
	dw Snare5
	dw Snare6
	dw Snare7
	dw HiHat2
	dw HiHat3
	dw Snare8
	dw Triangle3
	dw Triangle4
	dw Snare9
	dw Snare10
	dw Snare11
Drumkit2: ; e8e92
	dw Drum00
	dw Snare1
	dw Snare9
	dw Snare10
	dw Snare11
	dw Drum05
	dw Triangle1
	dw Triangle2
	dw HiHat1
	dw Snare5
	dw Snare6
	dw Snare7
	dw HiHat2
Drumkit3: ; e8eac
	dw Drum21
	dw Snare12
	dw Snare13
	dw Snare14
	dw Kick1
	dw Triangle5
	dw Drum20
	dw Drum27
	dw Drum28
	dw Drum29
	dw Drum21
	dw Kick2
	dw Crash2
Drumkit4: ; e8ec6
	dw Drum21
	dw Drum20
	dw Snare13
	dw Snare14
	dw Kick1
	dw Drum33
	dw Triangle5
	dw Drum35
	dw Drum31
	dw Drum32
	dw Drum36
	dw Kick2
	dw Crash1
Drumkit5: ; e8ee0
	dw Drum00
	dw Snare9
	dw Snare10
	dw Snare11
	dw Drum27
	dw Drum28
	dw Drum29
	dw Drum05
	dw Triangle1
	dw Crash1
	dw Snare14
	dw Snare13
	dw Kick2
; e8efa

Drum00: ; e8efa
; unused
	noise C#,  1, $11, $00
	endchannel
; e8efe

Snare1: ; e8efe
	noise C#,  1, $c1, $33
	endchannel
; e8f02

Snare2: ; e8f02
	noise C#,  1, $b1, $33
	endchannel
; e8f06

Snare3: ; e8f06
	noise C#,  1, $a1, $33
	endchannel
; e8f0a

Snare4: ; e8f0a
	noise C#,  1, $81, $33
	endchannel
; e8f0e

Drum05: ; e8f0e
	noise C#,  8, $84, $37
	noise C#,  7, $84, $36
	noise C#,  6, $83, $35
	noise C#,  5, $83, $34
	noise C#,  4, $82, $33
	noise C#,  3, $81, $32
	endchannel
; e8f21

Triangle1: ; e8f21
	noise C#,  1, $51, $2a
	endchannel
; e8f25

Triangle2: ; e8f25
	noise C#,  2, $41, $2b
	noise C#,  1, $61, $2a
	endchannel
; e8f2c

HiHat1: ; e8f2c
	noise C#,  1, $81, $10
	endchannel
; e8f30

Snare5: ; e8f30
	noise C#,  1, $82, $23
	endchannel
; e8f34

Snare6: ; e8f34
	noise C#,  1, $82, $25
	endchannel
; e8f38

Snare7: ; e8f38
	noise C#,  1, $82, $26
	endchannel
; e8f3c

HiHat2: ; e8f3c
	noise C#,  1, $a1, $10
	endchannel
; e8f40

HiHat3: ; e8f40
	noise C#,  1, $a2, $11
	endchannel
; e8f44

Snare8: ; e8f44
	noise C#,  1, $a2, $50
	endchannel
; e8f48

Triangle3: ; e8f48
	noise C#,  1, $a1, $18
	noise C#,  1, $31, $33
	endchannel
; e8f4f

Triangle4: ; e8f4f
	noise C#,  3, $91, $28
	noise C#,  1, $71, $18
	endchannel
; e8f56

Snare9: ; e8f56
	noise C#,  1, $91, $22
	endchannel
; e8f5a

Snare10: ; e8f5a
	noise C#,  1, $71, $22
	endchannel
; e8f5e

Snare11: ; e8f5e
	noise C#,  1, $61, $22
	endchannel
; e8f62

Drum20: ; e8f62
	noise C#,  1, $11, $11
	endchannel
; e8f66

Drum21: ; e8f66
	endchannel
; e8f67

Snare12: ; e8f67
	noise C#,  1, $91, $33
	endchannel
; e8f6b

Snare13: ; e8f6b
	noise C#,  1, $51, $32
	endchannel
; e8f6f

Snare14: ; e8f6f
	noise C#,  1, $81, $31
	endchannel
; e8f73

Kick1: ; e8f73
	noise C#,  1, $88, $6b
	noise C#,  1, $71, $00
	endchannel
; e8f7a

Triangle5: ; e8f7a
	noise D_,  1, $91, $18
	endchannel
; e8f7e

Drum27: ; e8f7e
	noise C#,  8, $92, $10
	endchannel
; e8f82

Drum28: ; e8f82
	noise D_,  4, $91, $00
	noise D_,  4, $11, $00
	endchannel
; e8f89

Drum29: ; e8f89
	noise D_,  4, $91, $11
	noise D_,  4, $11, $00
	endchannel
; e8f90

Crash1: ; e8f90
	noise D_,  4, $88, $15
	noise C#,  1, $65, $12
	endchannel
; e8f97

Drum31: ; e8f97
	noise D_,  4, $51, $21
	noise D_,  4, $11, $11
	endchannel
; e8f9e

Drum32: ; e8f9e
	noise D_,  4, $51, $50
	noise D_,  4, $11, $11
	endchannel
; e8fa5

Drum33: ; e8fa5
	noise C#,  1, $a1, $31
	endchannel
; e8fa9

Crash2: ; e8fa9
	noise C#,  1, $84, $12
	endchannel
; e8fad

Drum35: ; e8fad
	noise D_,  4, $81, $00
	noise D_,  4, $11, $00
	endchannel
; e8fb4

Drum36: ; e8fb4
	noise D_,  4, $81, $21
	noise D_,  4, $11, $11
	endchannel
; e8fbb

Kick2: ; e8fbb
	noise C#,  1, $a8, $6b
	noise C#,  1, $71, $00
	endchannel
; e8fc2

GetLRTracks: ; e8fc2
; gets the default sound l/r channels
; stores mono/stereo table in hl
	ld a, [Options]
	bit 5, a ; stereo
	; made redundant, could have had a purpose in gold
	jr nz, .stereo
	ld hl, MonoTracks
	ret

.stereo
	ld hl, StereoTracks
	ret

; e8fd1

MonoTracks: ; e8fd1
; bit corresponds to track #
; hi: left channel
; lo: right channel
	db $11, $22, $44, $88
; e8fd5

StereoTracks: ; e8fd5
; made redundant
; seems to be modified on a per-song basis
	db $11, $22, $44, $88
; e8fd9

ChannelPointers: ; e8fd9
; music channels
	dw Channel1
	dw Channel2
	dw Channel3
	dw Channel4
; sfx channels
	dw Channel5
	dw Channel6
	dw Channel7
	dw Channel8
; e8fe9

ClearChannels:: ; e8fe9
; runs ClearChannel for all 4 channels
; doesn't seem to be used, but functionally identical to MapSetup_Sound_Off
	ld hl, rNR50
	xor a
rept 2
	ld [hli], a
endr
	ld a, $80
	ld [hli], a
	ld hl, rNR10
	ld e, $4
.loop
	call ClearChannel
	dec e
	jr nz, .loop
	ret

; e8ffe

ClearChannel: ; e8ffe
; input: hl = beginning hw sound register (rNR10, rNR20, rNR30, rNR40)
; output: 00 00 80 00 80

;   sound channel   1      2      3      4
	xor a
	ld [hli], a ; rNR10, rNR20, rNR30, rNR40 ; sweep = 0

	ld [hli], a ; rNR11, rNR21, rNR31, rNR41 ; length/wavepattern = 0
	ld a, $8
	ld [hli], a ; rNR12, rNR22, rNR32, rNR42 ; envelope = 0
	xor a
	ld [hli], a ; rNR13, rNR23, rNR33, rNR43 ; frequency lo = 0
	ld a, $80
	ld [hli], a ; rNR14, rNR24, rNR34, rNR44 ; restart sound (freq hi = 0)
	ret

; e900a