/*
 * 最小 JSON Schema 校验器（够用就行，不引第三方依赖）
 * 支持子集：type(含 null 联合)、required、enum、maxItems、items、properties。
 * 契约必须真的被执行：文档里写必填，机器就必须拦得住缺失。
 */
function typeOf(v) {
  if (v === null) return 'null';
  if (Array.isArray(v)) return 'array';
  return typeof v;
}

export function validate(schema, value, path = '$') {
  let errors = [];
  if (schema.type) {
    const allowed = Array.isArray(schema.type) ? schema.type : [schema.type];
    if (!allowed.includes(typeOf(value))) {
      errors.push(`${path}: 类型应为 ${allowed.join('/')}，实际 ${value === undefined ? '缺失' : typeOf(value)}`);
      return errors;
    }
  }
  if (Array.isArray(schema.enum) && value !== undefined && !schema.enum.includes(value)) {
    errors.push(`${path}: 取值必须是 ${schema.enum.join('|')}，实际 ${JSON.stringify(value)}`);
  }
  if (typeOf(value) === 'object') {
    (schema.required || []).forEach(k => {
      if (value[k] === undefined) errors.push(`${path}.${k}: 缺少必填字段`);
    });
    Object.keys(schema.properties || {}).forEach(k => {
      if (value[k] !== undefined) errors = errors.concat(validate(schema.properties[k], value[k], `${path}.${k}`));
    });
  }
  if (typeOf(value) === 'array') {
    if (schema.maxItems !== undefined && value.length > schema.maxItems) {
      errors.push(`${path}: 条数 ${value.length} 超过上限 ${schema.maxItems}`);
    }
    if (schema.items) value.forEach((x, i) => { errors = errors.concat(validate(schema.items, x, `${path}[${i}]`)); });
  }
  return errors;
}
