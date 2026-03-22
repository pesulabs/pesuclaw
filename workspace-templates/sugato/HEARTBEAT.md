# Heartbeat — Sugaclaw

## Estado actual

Los heartbeats automáticos se configurarán como crons en pesuclaw a medida que se definan.
Este archivo documenta los checks que estarán activos.

---

## Checks activos

_(ninguno todavía — se agregan desde pesuclaw crons)_

---

## Plantillas disponibles para activar

### Daily morning check
- Open loops del día anterior sin resolver
- Tareas con deadline hoy o mañana
- Clientes con seguimiento pendiente

### Weekly review (lunes)
- Proyectos activos: estado y próximos pasos
- Leads en pipeline: qué avanzó, qué se estancó
- Items diferidos más de dos veces: forzar decisión do/delegate/drop

### Trigger-based
- Nuevo cliente agregado → confirmar onboarding iniciado
- Propuesta enviada → recordatorio de follow-up en N días
- Proyecto marcado como cerrado → revisar facturación y feedback
